#!/usr/bin/env python3
"""Isolated stdlib tests for the Boxcare fleet-maintenance command."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import time
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
BOXCARE = REPO_ROOT / "boxcare" / ".local" / "bin" / "boxcare"
TRACKED_INVENTORY = (
    REPO_ROOT / "boxcare" / ".config" / "boxcare" / "hosts.json"
)


class BoxcareTestCase(unittest.TestCase):
    maxDiff = None

    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="boxcare-test-")
        self.addCleanup(self.tempdir.cleanup)
        self.tmp = Path(self.tempdir.name)
        self.ssh_log = self.tmp / "ssh.jsonl"

    def write_inventory(self, hosts: list[dict], **default_overrides: int) -> Path:
        defaults = {
            "jobs_audit": 4,
            "jobs_update": 1,
            "connect_timeout_s": 2,
            "command_timeout_s": 10,
            "transaction_warn_after_s": 5,
            "disk_warn_pct": 80,
            "disk_crit_pct": 90,
            "inode_warn_pct": 80,
            "inode_crit_pct": 90,
        }
        defaults.update(default_overrides)
        path = self.tmp / "hosts.json"
        path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "defaults": defaults,
                    "hosts": hosts,
                }
            ),
            encoding="utf-8",
            newline="\n",
        )
        return path

    @staticmethod
    def host(host_id: str, *tags: str, enabled: bool = True) -> dict:
        return {
            "id": host_id,
            "label": host_id.title(),
            "ssh_alias": host_id,
            "enabled": enabled,
            "distro": "auto",
            "tags": list(tags),
            "expected_mounts": ["/"],
            "allowed_tcp_listeners": [],
            "allowed_udp_listeners": [],
        }

    def write_fake_ssh(self, *, delay_s: float = 0.0) -> Path:
        bindir = self.tmp / "bin"
        bindir.mkdir(exist_ok=True)
        ssh = bindir / "ssh"
        ssh.write_text(
            "#!/usr/bin/env python3\n"
            + textwrap.dedent(
                f"""
                import base64
                import json
                import os
                import sys
                import time

                remote_script = sys.stdin.read()
                with open(os.environ["BOXCARE_SSH_LOG"], "a", encoding="utf-8") as log:
                    print(
                        json.dumps({{"argv": sys.argv[1:], "stdin": remote_script}}),
                        file=log,
                    )
                time.sleep({delay_s!r})
                checks = (
                    "identity",
                    "uptime",
                    "disk",
                    "memory",
                    "failed_units",
                    "listeners",
                    "firewall",
                    "sshd",
                    "auto_updates",
                    "kernel_warnings",
                    "reboot_required",
                    "pi_health",
                )
                if "update_plan" in remote_script:
                    value = base64.b64encode(b"platform=arch\\ncached_only=true\\n").decode("ascii")
                    print(f"BOXCARE1\\tupdate_plan\\tok\\t{{value}}")
                    raise SystemExit(0)
                for name in checks:
                    value = base64.b64encode(b"fixture").decode("ascii")
                    print(f"BOXCARE1\\t{{name}}\\tok\\t{{value}}")
                """
            ).lstrip(),
            encoding="utf-8",
            newline="\n",
        )
        ssh.chmod(0o755)
        return bindir

    def run_boxcare(
        self,
        *args: str,
        inventory: Path,
        fake_bin: Path | None = None,
        timeout: float = 15,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["BOXCARE_SSH_LOG"] = str(self.ssh_log)
        if fake_bin is not None:
            env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"
        return subprocess.run(
            [str(BOXCARE), *args, "--inventory", str(inventory)],
            text=True,
            capture_output=True,
            check=False,
            env=env,
            timeout=timeout,
        )

    def ssh_calls(self) -> list[dict]:
        if not self.ssh_log.exists():
            return []
        return [
            json.loads(line)
            for line in self.ssh_log.read_text(encoding="utf-8").splitlines()
        ]


class InventoryTests(BoxcareTestCase):
    def test_tracked_inventory_is_safe_schema_v1(self) -> None:
        inventory = json.loads(TRACKED_INVENTORY.read_text(encoding="utf-8"))
        self.assertEqual(inventory["schema_version"], 1)
        self.assertEqual(inventory["defaults"]["jobs_audit"], 4)
        self.assertEqual(inventory["defaults"]["jobs_update"], 1)

        hosts = {host["id"]: host for host in inventory["hosts"]}
        self.assertEqual(set(hosts), {"ordijul", "pixel", "pi5", "pi3", "vps"})
        self.assertEqual(hosts["ordijul"]["ssh_alias"], "local")
        self.assertFalse(hosts["pixel"]["enabled"])
        self.assertTrue(all(host["distro"] == "auto" for host in hosts.values()))

        forbidden_keys = {
            "address",
            "hostname",
            "ip",
            "key",
            "password",
            "port",
            "private_key",
            "user",
            "username",
        }
        for host in hosts.values():
            self.assertTrue(forbidden_keys.isdisjoint(host))
            self.assertNotIn("@", host["ssh_alias"])
            self.assertEqual(host["allowed_tcp_listeners"], [])
            self.assertEqual(host["allowed_udp_listeners"], [])

    def test_inventory_rejects_non_string_host_list_values(self) -> None:
        host = self.host("alpha")
        host["important_units"] = [["not-a-unit"]]
        inventory = self.write_inventory([host])

        result = self.run_boxcare("audit", inventory=inventory)

        self.assertEqual(result.returncode, 8)
        self.assertIn("important_units must contain only strings", result.stderr)


class CommandTests(BoxcareTestCase):
    def test_host_and_tag_selection_only_contacts_the_intersection(self) -> None:
        inventory = self.write_inventory(
            [
                self.host("alpha", "pi", "server"),
                self.host("beta", "server"),
                self.host("gamma", "pi", enabled=False),
            ]
        )
        fake_bin = self.write_fake_ssh()

        result = self.run_boxcare(
            "audit",
            "--host",
            "alpha",
            "--tag",
            "pi",
            "--format",
            "json",
            inventory=inventory,
            fake_bin=fake_bin,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual([item["id"] for item in report["results"]], ["alpha"])
        calls = self.ssh_calls()
        self.assertEqual(len(calls), 1)
        self.assertIn("alpha", calls[0]["argv"])
        self.assertNotIn("beta", calls[0]["argv"])
        self.assertIn("BatchMode=yes", calls[0]["argv"])
        self.assertIn("StrictHostKeyChecking=yes", calls[0]["argv"])

    def test_jobs_control_parallel_host_execution(self) -> None:
        inventory = self.write_inventory(
            [self.host(f"host-{number}", "fleet") for number in range(4)]
        )
        fake_bin = self.write_fake_ssh(delay_s=0.2)

        started = time.monotonic()
        serial = self.run_boxcare(
            "audit",
            "--jobs",
            "1",
            "--format",
            "json",
            inventory=inventory,
            fake_bin=fake_bin,
        )
        serial_elapsed = time.monotonic() - started
        self.ssh_log.unlink(missing_ok=True)

        started = time.monotonic()
        parallel = self.run_boxcare(
            "audit",
            "--jobs",
            "4",
            "--format",
            "json",
            inventory=inventory,
            fake_bin=fake_bin,
        )
        parallel_elapsed = time.monotonic() - started

        self.assertEqual(serial.returncode, 0, serial.stderr)
        self.assertEqual(parallel.returncode, 0, parallel.stderr)
        self.assertEqual(len(self.ssh_calls()), 4)
        self.assertLess(parallel_elapsed, serial_elapsed * 0.7)

    def test_json_and_jsonl_are_machine_parseable(self) -> None:
        inventory = self.write_inventory([self.host("alpha", "fleet")])
        fake_bin = self.write_fake_ssh()

        json_result = self.run_boxcare(
            "audit",
            "--format",
            "json",
            inventory=inventory,
            fake_bin=fake_bin,
        )
        self.assertEqual(json_result.returncode, 0, json_result.stderr)
        report = json.loads(json_result.stdout)
        self.assertEqual(report["schema_version"], 1)
        self.assertEqual(report["operation"], "audit")
        self.assertEqual(report["results"][0]["id"], "alpha")
        self.assertIsInstance(report["results"][0]["checks"], list)
        self.assertIn("summary", report)

        jsonl_result = self.run_boxcare(
            "audit",
            "--format",
            "jsonl",
            inventory=inventory,
            fake_bin=fake_bin,
        )
        self.assertEqual(jsonl_result.returncode, 0, jsonl_result.stderr)
        records = [json.loads(line) for line in jsonl_result.stdout.splitlines()]
        self.assertEqual(records[0]["type"], "host")
        self.assertEqual(records[0]["id"], "alpha")
        self.assertEqual(records[-1]["type"], "summary")

    def test_update_dry_run_does_not_send_mutating_commands(self) -> None:
        inventory = self.write_inventory([self.host("alpha", "arch")])
        fake_bin = self.write_fake_ssh()

        result = self.run_boxcare(
            "update",
            "--dry-run",
            "--format",
            "json",
            inventory=inventory,
            fake_bin=fake_bin,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["results"][0]["platform"], "arch")
        calls = self.ssh_calls()
        self.assertGreaterEqual(len(calls), 1)
        remote_payload = "\n".join(call["stdin"] for call in calls)
        forbidden = (
            "apt-get update",
            "apt-get upgrade",
            "pacman -Syu",
            "pkg upgrade",
            "yay --repo -Syu",
        )
        for command in forbidden:
            self.assertNotIn(command, remote_payload)


if __name__ == "__main__":
    unittest.main(verbosity=2)

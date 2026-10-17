from __future__ import annotations

import asyncio
import inspect
import os
import select
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import textwrap
import time
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import bwsession
from jujutui.clipboard import (
    SUPERVISOR_READY_TIMEOUT,
    _wait_for_supervisor,
    copy,
    kill_owned_clipboards,
)
from jujutui.clipboard_supervisor import STATUS_POLL_INTERVAL
from jujutui.config import configured_ttl_hours
from jujutui.bw_card import main as bw_card_main
from jujutui.bw_unlock_card import main as bw_unlock_card_main
from jujutui.floating import FOOT_TTY_MARKER, launch_floating, terminal_route
from jujutui.security import sanitize_display
from jujutui.session import (
    SessionCancelled,
    SessionExpired,
    SessionLocked,
    item_meta,
    item_secret,
    require_unlocked,
    status_snapshot,
)


def _make_stow_fake_home(root: Path) -> dict[str, Path]:
    """Install launchers and fake bwsession as GNU Stow's per-file symlinks."""
    local = root / ".local"
    lib = local / "lib"
    bin_dir = local / "bin"
    lib.mkdir(parents=True)
    bin_dir.mkdir(parents=True)
    source_package = Path("tui/.local/lib/jujutui").resolve()
    target_package = lib / "jujutui"
    target_package.mkdir()
    for source in source_package.iterdir():
        if source.is_file() and not source.name.endswith(".pyc"):
            (target_package / source.name).symlink_to(source)
    fake_package = lib / "bwsession"
    fake_package.mkdir()
    (fake_package / "__init__.py").symlink_to(
        Path("tui/tests/fakes/bwsession.py").resolve()
    )
    for name in ("bw-card", "bw-unlock-card"):
        (bin_dir / name).symlink_to((Path("tui/.local/bin") / name).resolve())

    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    os.chmod(runtime, 0o700)
    fake_bin = root / "fake-bin"
    fake_bin.mkdir()
    foot = fake_bin / "foot"
    foot.write_text(
        "#!/usr/bin/python3 -I\n"
        "import os, pty, select, subprocess, sys, time\n"
        "args = sys.argv[1:]\n"
        "command = args[args.index('--') + 1:]\n"
        "master, slave = pty.openpty()\n"
        "child = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=os.environ.copy(), close_fds=True)\n"
        "os.close(slave)\n"
        "started = time.monotonic()\n"
        "first_at = float(os.environ.get('FAKE_FOOT_FIRST_DELAY', '0.6'))\n"
        "second_at = float(os.environ.get('FAKE_FOOT_SECOND_DELAY', '1.1'))\n"
        "first = os.environ.get('FAKE_FOOT_INPUT_1')\n"
        "second = os.environ.get('FAKE_FOOT_INPUT_2')\n"
        "captured = bytearray()\n"
        "sent_first = sent_second = False\n"
        "deadline = started + float(os.environ.get('FAKE_FOOT_TIMEOUT', '5'))\n"
        "while child.poll() is None and time.monotonic() < deadline:\n"
        "    elapsed = time.monotonic() - started\n"
        "    if first is not None and not sent_first and elapsed >= first_at:\n"
        "        os.write(master, os.fsencode(first)); sent_first = True\n"
        "    if second is not None and not sent_second and elapsed >= second_at:\n"
        "        os.write(master, os.fsencode(second)); sent_second = True\n"
        "    ready, _, _ = select.select([master], [], [], 0.02)\n"
        "    if ready:\n"
        "        try: captured.extend(os.read(master, 4096))\n"
        "        except OSError: break\n"
        "capture_path = os.environ.get('FAKE_FOOT_CAPTURE_PATH')\n"
        "if capture_path:\n"
        "    with open(capture_path, 'wb') as handle: handle.write(captured)\n"
        "if child.poll() is None:\n"
        "    child.kill(); child.wait(); sys.exit(124)\n"
        "sys.exit(child.returncode)\n",
        encoding="utf-8",
    )
    foot.chmod(0o755)
    return {"home": root, "runtime": runtime, "bin": fake_bin, "launcher_bin": bin_dir}


async def _wait_for(predicate, timeout: float = 1.5) -> bool:
    loop = asyncio.get_running_loop()
    deadline = loop.time() + timeout
    while loop.time() < deadline:
        if predicate():
            return True
        await asyncio.sleep(0.01)
    return bool(predicate())


class ContractTests(unittest.TestCase):
    def setUp(self) -> None:
        bwsession.reset_metrics()
        bwsession.STATE = "unlocked"
        bwsession.GENERATION = "a1b2c3d4"
        bwsession.CANCEL_TOKEN = "0123456789abcdef"
        bwsession.DESKTOP_UNLOCKED = True
        bwsession.CALLS.clear()

    def test_status_and_metadata_contract(self) -> None:
        self.assertEqual(status_snapshot()["state"], "unlocked")
        self.assertEqual(item_meta("12345678-1234-1234-1234-123456789abc")["name"], "Example <item>")

    def test_card_does_not_read_metadata_without_textual(self) -> None:
        from jujutui.base import TextualUnavailable

        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_card.terminal_route", return_value="inline"), patch(
            "jujutui.base.create_card_app_class", side_effect=TextualUnavailable
        ), patch.object(
            bwsession, "meta"
        ) as meta, patch("jujutui.bw_card._fail", return_value=2) as fail:
            self.assertEqual(bw_card_main(["item_1"]), 2)
        meta.assert_not_called()
        fail.assert_called_once_with("Textual is required for Bitwarden cards.")

    def test_headless_item_card_reexecs_in_floating_window_and_propagates_status(self) -> None:
        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_card.terminal_route", return_value="launch"), patch(
            "jujutui.bw_card.launch_floating", return_value=3
        ) as launch, patch.object(bwsession, "meta") as meta:
            self.assertEqual(bw_card_main(["item_1"]), 3)
        launch.assert_called_once_with(
            [str(Path.home() / ".local" / "bin" / "bw-card"), "item_1"],
            wait=True,
        )
        meta.assert_not_called()

    def test_headless_item_card_preserves_generation_binding(self) -> None:
        args = ["item_1", "--generation", "a1b2c3d4"]
        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_card.terminal_route", return_value="launch"), patch(
            "jujutui.bw_card.launch_floating", return_value=0
        ) as launch:
            self.assertEqual(bw_card_main(args), 0)
        launch.assert_called_once_with(
            [str(Path.home() / ".local" / "bin" / "bw-card"), *args],
            wait=True,
        )

    def test_item_card_refuses_mismatched_generation_with_fixed_message(self) -> None:
        from jujutui.bw_card import _GENERATION_CHANGED_MESSAGE

        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_card.terminal_route", return_value="inline"), patch(
            "jujutui.bw_card._fail", return_value=2
        ) as fail, patch.object(bwsession, "meta") as meta:
            self.assertEqual(
                bw_card_main(["item_1", "--generation", "deadbeef"]), 2
            )
        fail.assert_called_once_with(_GENERATION_CHANGED_MESSAGE)
        meta.assert_not_called()

    def test_item_card_rejects_malformed_generation_as_usage_error(self) -> None:
        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_card.terminal_route", return_value="inline"), patch(
            "jujutui.bw_card._fail", return_value=2
        ) as fail:
            self.assertEqual(
                bw_card_main(["item_1", "--generation", "not-a-generation"]), 2
            )
        fail.assert_called_once_with(
            "Usage: bw-card ITEM_ID [--generation GENERATION]"
        )

    def test_headless_unlock_card_reexecs_and_propagates_cancel_status(self) -> None:
        with patch("jujutui.bw_unlock_card.apply_process_hardening"), patch(
            "jujutui.bw_unlock_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_unlock_card.terminal_route", return_value="launch"), patch(
            "jujutui.bw_unlock_card.launch_floating", return_value=3
        ) as launch, patch("jujutui.instance.acquire_unlock_card_lock") as acquire:
            self.assertEqual(bw_unlock_card_main([]), 3)
        launch.assert_called_once_with(
            [str(Path.home() / ".local" / "bin" / "bw-unlock-card")],
            wait=True,
        )
        acquire.assert_not_called()

    def test_locked_desktop_dismisses_unlock_card_before_prompt(self) -> None:
        bwsession.DESKTOP_UNLOCKED = False
        with patch("jujutui.bw_unlock_card.apply_process_hardening"), patch(
            "jujutui.bw_unlock_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_unlock_card.terminal_route", return_value="inline"), patch(
            "jujutui.instance.acquire_unlock_card_lock"
        ) as acquire, patch(
            "jujutui.bw_unlock_card.launch_floating"
        ) as launch:
            self.assertEqual(bw_unlock_card_main([]), 3)
        acquire.assert_not_called()
        launch.assert_not_called()

    def test_fake_unlock_contract_rejects_desktop_lock_before_commit(self) -> None:
        bwsession.DESKTOP_UNLOCKED = False
        with self.assertRaises(bwsession.Error):
            bwsession.unlock(b"test-password", desktop=True)
        self.assertEqual(
            bwsession.CALLS,
            [
                ("unlock_ticket", "0123456789abcdef"),
                ("unlock", b"test-password", True, "0123456789abcdef"),
            ],
        )

    def test_unlock_race_with_desktop_lock_is_reported_as_dismissal(self) -> None:
        captured = {}
        lock_fd = os.open(os.devnull, os.O_RDONLY)

        def capture_app(app):
            captured["app"] = app
            return 0

        with patch("jujutui.bw_unlock_card.apply_process_hardening"), patch(
            "jujutui.bw_unlock_card.terminal_route", return_value="inline"
        ), patch("jujutui.instance.acquire_unlock_card_lock", return_value=lock_fd), patch(
            "jujutui.bw_unlock_card._run", side_effect=capture_app
        ):
            self.assertEqual(bw_unlock_card_main([]), 0)

        bwsession.DESKTOP_UNLOCKED = False
        from jujutui.bw_unlock_card import _CancelExitCode

        result = captured["app"]._unlock_in_thread(
            b"test-password",
            threading.Event(),
            bwsession.CANCEL_TOKEN,
            _CancelExitCode(),
            threading.Event(),
        )
        self.assertEqual(result, ("cancelled", None, None))

    def test_python_launchers_use_isolated_interpreter(self) -> None:
        for launcher in Path("tui/.local/bin").iterdir():
            if launcher.is_file():
                self.assertEqual(launcher.read_text(encoding="utf-8").splitlines()[0], "#!/usr/bin/python3 -I")
        supervisor = Path("tui/.local/lib/jujutui/clipboard_supervisor.py")
        self.assertEqual(supervisor.read_text(encoding="utf-8").splitlines()[0], "#!/usr/bin/python3 -I")

    def test_duplicate_unlock_card_uses_distinct_exit_code_four(self) -> None:
        from jujutui.instance import InstanceAlreadyRunning

        with patch("jujutui.bw_unlock_card.apply_process_hardening"), patch(
            "jujutui.bw_unlock_card.clear_textual_debug_environment"
        ), patch("jujutui.bw_unlock_card.terminal_route", return_value="inline"), patch(
            "jujutui.instance.acquire_unlock_card_lock",
            side_effect=InstanceAlreadyRunning,
        ):
            self.assertEqual(bw_unlock_card_main([]), 4)

    def test_secret_uses_and_rechecks_generation(self) -> None:
        secret = item_secret("item_1", "username", "a1b2c3d4")
        self.assertEqual(secret, b"synthetic-test-value")
        self.assertIn(("secret", "item_1", "username", "a1b2c3d4"), bwsession.CALLS)
        with self.assertRaises(SessionExpired):
            item_secret("item_1", "password", "deadbeef")

    def test_lock_fails_closed(self) -> None:
        bwsession.STATE = "locked"
        with self.assertRaises(SessionLocked):
            require_unlocked()

    def test_status_rejects_expired_deadline(self) -> None:
        with patch.object(
            bwsession,
            "status",
            return_value={
                "schema": 1,
                "state": "unlocked",
                "deadline": int(time.time()) - 1,
                "generation": "a1b2c3d4",
                "message": "fixed test state",
            },
        ):
            with self.assertRaises(SessionExpired):
                status_snapshot()

    def test_display_text_removes_controls_and_bidi(self) -> None:
        self.assertEqual(sanitize_display("safe\n\u202eevil\x1b[31m"), "safe evil [31m")

    def test_sensitive_copy_uses_flag_and_owned_supervisor(self) -> None:
        supervisor = MagicMock()
        supervisor.poll.return_value = None
        with patch("jujutui.clipboard.shutil.which", return_value="/usr/bin/wl-copy"), patch(
            "jujutui.clipboard.subprocess.Popen", return_value=supervisor
        ) as popen, patch("jujutui.clipboard._wait_for_supervisor", return_value=True):
            handle = copy(
                b"synthetic-test-value",
                sensitive=True,
                ttl=30,
                expected_generation="a1b2c3d4",
            )
            supervisor_command = popen.call_args.args[0]
            self.assertNotIn(b"synthetic-test-value", " ".join(supervisor_command).encode())
            self.assertEqual(supervisor_command[1], "-I")
            self.assertEqual(supervisor_command[3:6], ["/usr/bin/wl-copy", "a1b2c3d4", "1"])
            self.assertEqual(supervisor_command[7], str(len(b"synthetic-test-value")))
            supervisor.stdin.write.assert_called_once_with(b"synthetic-test-value")
            self.assertIs(handle.supervisor, supervisor)
        kill_owned_clipboards()

    def test_regular_copy_uses_stdin_and_owned_supervisor(self) -> None:
        supervisor = MagicMock()
        supervisor.poll.return_value = None
        with patch("jujutui.clipboard.shutil.which", return_value="/usr/bin/wl-copy"), patch(
            "jujutui.clipboard.subprocess.Popen", return_value=supervisor
        ) as popen, patch("jujutui.clipboard._wait_for_supervisor", return_value=True):
            handle = copy(
                b"synthetic-test-value",
                sensitive=False,
                ttl=30,
                expected_generation="a1b2c3d4",
            )
            supervisor_command = popen.call_args.args[0]
            self.assertNotIn(b"synthetic-test-value", " ".join(supervisor_command).encode())
            self.assertIn("a1b2c3d4", supervisor_command)
            self.assertEqual(supervisor_command[1], "-I")
            self.assertEqual(supervisor_command[5], "0")
            self.assertEqual(supervisor_command[7], str(len(b"synthetic-test-value")))
            supervisor.stdin.write.assert_called_once_with(b"synthetic-test-value")
            self.assertIs(handle.supervisor, supervisor)
        kill_owned_clipboards()

    def test_supervisor_ready_wait_accounts_for_status_timeout(self) -> None:
        self.assertGreaterEqual(SUPERVISOR_READY_TIMEOUT, 25.0)
        self.assertGreaterEqual(STATUS_POLL_INTERVAL, 2.0)
        self.assertLessEqual(STATUS_POLL_INTERVAL, 5.0)
        with patch("jujutui.clipboard.select.select", return_value=([11], [], [])) as wait, patch(
            "jujutui.clipboard.os.read", return_value=b"1"
        ):
            self.assertTrue(_wait_for_supervisor(11))
        self.assertGreaterEqual(wait.call_args.args[3], SUPERVISOR_READY_TIMEOUT - 0.01)

    def _make_stow_supervisor_layout(self, root: Path, *, status_delay: float = 0.0):
        repo_root = Path(__file__).resolve().parents[2]
        home = root / "home"
        library_root = home / ".local" / "lib"
        source_root = root / "dotfiles"
        source_jujutui = source_root / "tui" / ".local" / "lib" / "jujutui"
        source_bwsession = source_root / "bitwarden" / ".local" / "lib" / "bwsession"
        installed_jujutui = library_root / "jujutui"
        installed_bwsession = library_root / "bwsession"
        source_jujutui.mkdir(parents=True)
        source_bwsession.mkdir(parents=True)
        installed_jujutui.mkdir(parents=True)
        installed_bwsession.mkdir(parents=True)
        for source in (repo_root / "tui/.local/lib/jujutui").glob("*.py"):
            target = source_jujutui / source.name
            target.symlink_to(source)
            (installed_jujutui / source.name).symlink_to(target)

        fake_init = source_bwsession / "__init__.py"
        fake_init.write_text(
            "import os, time\n"
            "from pathlib import Path\n"
            "def status():\n"
            "    calls = Path(os.environ['STATUS_CALLS'])\n"
            "    count = int(calls.read_text() or '0') if calls.exists() else 0\n"
            f"    time.sleep({status_delay!r} if count == 0 else 0)\n"
            "    if count > 0 and os.environ.get('SLOW_STATUS_SECONDS'):\n"
            "        time.sleep(float(os.environ['SLOW_STATUS_SECONDS']))\n"
            "    next_count = count + 1; calls.write_text(str(next_count))\n"
            "    locked = bool(os.environ.get('LOCK_AFTER')) and next_count > int(os.environ['LOCK_AFTER'])\n"
            "    state = 'locked' if locked else 'unlocked'\n"
            "    return {'schema': 1, 'state': state, 'generation': None if locked else "
            "'a1b2c3d4', 'deadline': None if locked else int(time.time()) + 3600}\n"
            "def meta(item_id):\n"
            "    return {'name': 'Synthetic item', 'username': 'synthetic-user', "
            "'uris': ['https://example.test']}\n"
            "def secret(item_id, field, generation):\n"
            "    return b'synthetic-secret'\n"
            "def unlock(password, desktop=True):\n"
            "    if desktop and not desktop_unlocked(): raise Error('synthetic desktop lock')\n"
            "    if password != b'test-password': raise Exception('synthetic failure')\n"
            "class Error(Exception): pass\n"
            "def cancel_unlocks(): pass\n"
            "def desktop_unlocked(): return os.environ.get('DESKTOP_LOCKED') != '1'\n",
            encoding="utf-8",
        )
        (installed_bwsession / "__init__.py").symlink_to(fake_init)

        bin_dir = root / "bin"
        bin_dir.mkdir()
        wl_copy = bin_dir / "wl-copy"
        wl_copy.write_text(
            "#!/usr/bin/python3 -I\n"
            "import json, os, sys, time\n"
            "from pathlib import Path\n"
            "Path(os.environ['PROVIDER_PID']).write_text(str(os.getpid()))\n"
            "Path(os.environ['PROVIDER_ARGS']).write_text(json.dumps(sys.argv[1:]))\n"
            "data = sys.stdin.buffer.read()\n"
            "Path(os.environ['PROVIDER_LENGTH']).write_text(str(len(data)))\n"
            "while True: time.sleep(.05)\n",
            encoding="utf-8",
        )
        wl_copy.chmod(0o755)
        return {
            "home": home,
            "supervisor": installed_jujutui / "clipboard_supervisor.py",
            "wl_copy": wl_copy,
            "env": {
                "HOME": str(home),
                "PATH": f"{bin_dir}:/usr/bin",
                "STATUS_CALLS": str(root / "status-calls"),
                "PROVIDER_PID": str(root / "provider-pid"),
                "PROVIDER_ARGS": str(root / "provider-args"),
                "PROVIDER_LENGTH": str(root / "provider-length"),
                "SLOW_STATUS_SECONDS": "",
            },
        }

    @staticmethod
    def _proc_state(pid: int) -> str | None:
        try:
            stat_line = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
            return stat_line[stat_line.rfind(")") + 2 :].split()[0]
        except (OSError, IndexError):
            return None

    def _wait_process_dead(self, pid: int, timeout: float = 3.0) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self._proc_state(pid) in (None, "Z"):
                return True
            time.sleep(0.05)
        return self._proc_state(pid) in (None, "Z")

    def test_supervisor_works_in_two_package_stow_layout_and_owns_provider(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = self._make_stow_supervisor_layout(Path(temporary))
            env = fixture["env"].copy()
            env["XDG_RUNTIME_DIR"] = temporary
            self.assertNotIn("PYTHONPATH", env)
            ready_read, ready_write = os.pipe()
            supervisor = None
            try:
                supervisor = subprocess.Popen(
                    [
                        sys.executable,
                        "-I",
                        str(fixture["supervisor"]),
                        str(fixture["wl_copy"]),
                        "a1b2c3d4",
                        "1",
                        "30",
                        str(len(b"synthetic-test-value")),
                        str(ready_write),
                    ],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=env,
                    close_fds=True,
                    pass_fds=(ready_write,),
                )
                os.close(ready_write)
                ready_write = -1
                readable, _, _ = select.select([ready_read], [], [], 5.0)
                self.assertTrue(readable, "supervisor did not finish the bounded status check")
                self.assertEqual(os.read(ready_read, 1), b"1")
                supervisor.stdin.write(b"synthetic-test-value")
                supervisor.stdin.close()
                length_path = Path(env["PROVIDER_LENGTH"])
                deadline = time.monotonic() + 3.0
                while not length_path.exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertEqual(length_path.read_text(), str(len(b"synthetic-test-value")))
                provider_pid = int(Path(env["PROVIDER_PID"]).read_text())
                provider_args = __import__("json").loads(Path(env["PROVIDER_ARGS"]).read_text())
                self.assertEqual(
                    provider_args,
                    ["--foreground", "--type", "text/plain;charset=utf-8", "--sensitive"],
                )
                supervisor.kill()
                supervisor.wait(timeout=3)
                self.assertTrue(self._wait_process_dead(provider_pid))
            finally:
                os.close(ready_read)
                if ready_write >= 0:
                    os.close(ready_write)
                if supervisor is not None and supervisor.poll() is None:
                    supervisor.kill()
                    supervisor.wait(timeout=3)

    def test_card_death_during_supervisor_handshake_kills_provider(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = self._make_stow_supervisor_layout(Path(temporary), status_delay=0.6)
            env = fixture["env"].copy()
            driver = textwrap.dedent(
                """
                import os, subprocess, sys
                read_fd, write_fd = os.pipe()
                child = subprocess.Popen(
                    [sys.executable, '-I', os.environ['SUPERVISOR'],
                     os.environ['WL_COPY'], 'a1b2c3d4', '0', '30', '12', str(write_fd)],
                    stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, close_fds=True, pass_fds=(write_fd,),
                    start_new_session=True)
                os.close(write_fd)
                open(os.environ['SUPERVISOR_PID'], 'w').write(str(child.pid))
                os._exit(23)
                """
            )
            env.update(
                {
                    "SUPERVISOR": str(fixture["supervisor"]),
                    "WL_COPY": str(fixture["wl_copy"]),
                    "SUPERVISOR_PID": str(Path(temporary) / "supervisor-pid"),
                }
            )
            card = subprocess.run(
                [sys.executable, "-I", "-c", driver],
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3,
                check=False,
            )
            self.assertEqual(card.returncode, 23)
            supervisor_pid_path = Path(env["SUPERVISOR_PID"])
            deadline = time.monotonic() + 5.0
            while not supervisor_pid_path.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(supervisor_pid_path.exists())
            supervisor_pid = int(supervisor_pid_path.read_text())
            provider_pid_path = Path(env["PROVIDER_PID"])
            deadline = time.monotonic() + 3.0
            while not provider_pid_path.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            if provider_pid_path.exists():
                provider_pid = int(provider_pid_path.read_text())
                self.assertTrue(self._wait_process_dead(provider_pid))
            self.assertTrue(self._wait_process_dead(supervisor_pid))

    def test_supervisor_ttl_kills_provider_while_status_is_blocked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            fixture = self._make_stow_supervisor_layout(Path(temporary))
            env = fixture["env"].copy()
            env["SLOW_STATUS_SECONDS"] = "5"
            ready_read, ready_write = os.pipe()
            supervisor = None
            try:
                supervisor = subprocess.Popen(
                    [
                        sys.executable,
                        "-I",
                        str(fixture["supervisor"]),
                        str(fixture["wl_copy"]),
                        "a1b2c3d4",
                        "0",
                        "1",
                        str(len(b"synthetic-ttl")),
                        str(ready_write),
                    ],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=env,
                    close_fds=True,
                    pass_fds=(ready_write,),
                )
                os.close(ready_write)
                ready_write = -1
                readable, _, _ = select.select([ready_read], [], [], 5.0)
                self.assertTrue(readable)
                self.assertEqual(os.read(ready_read, 1), b"1")
                supervisor.stdin.write(b"synthetic-ttl")
                supervisor.stdin.close()
                provider_pid_path = Path(env["PROVIDER_PID"])
                deadline = time.monotonic() + 2.0
                while not provider_pid_path.exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                provider_pid = int(provider_pid_path.read_text())
                self.assertTrue(self._wait_process_dead(provider_pid, timeout=2.5))
                self.assertIsNone(supervisor.poll())
                supervisor.kill()
                supervisor.wait(timeout=3)
            finally:
                os.close(ready_read)
                if ready_write >= 0:
                    os.close(ready_write)
                if supervisor is not None and supervisor.poll() is None:
                    supervisor.kill()
                    supervisor.wait(timeout=3)

    def test_foot_launcher_uses_fixed_safe_window_options(self) -> None:
        with patch.dict(
            os.environ,
            {"BW_SESSION": "synthetic-session", "PYTHONPATH": "/tmp/untrusted", "PYTHONHOME": "/tmp/untrusted"},
        ), patch("jujutui.floating.shutil.which", return_value="/usr/bin/foot"), patch(
            "jujutui.floating.subprocess.Popen"
        ) as popen:
            launch_floating(["bw-card", "12345678-1234-1234-1234-123456789abc"])
        command = popen.call_args.args[0]
        self.assertEqual(command[1:3], ["--app-id=jujutui-card", "--title=Bitwarden"])
        self.assertIn("scrollback.lines=0", command)
        self.assertIn("security.osc52=disabled", command)
        self.assertEqual(command[-3:], ["--", "bw-card", "12345678-1234-1234-1234-123456789abc"])
        env = popen.call_args.kwargs["env"]
        self.assertNotIn("BW_SESSION", env)
        self.assertNotIn("PYTHONPATH", env)
        self.assertNotIn("PYTHONHOME", env)
        self.assertEqual(env[FOOT_TTY_MARKER], "1")

    def test_floating_wait_propagates_child_status(self) -> None:
        completed = subprocess.CompletedProcess(["foot"], 3)
        with patch("jujutui.floating.shutil.which", return_value="/usr/bin/foot"), patch(
            "jujutui.floating.subprocess.run", return_value=completed
        ) as run:
            self.assertEqual(launch_floating(["bw-unlock-card"], wait=True), 3)
        self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(run.call_args.kwargs["stdout"], subprocess.DEVNULL)

    def test_terminal_route_requires_one_dedicated_tty_on_all_three_streams(self) -> None:
        for mask in range(8):
            is_tty = {fd: bool(mask & (1 << fd)) for fd in (0, 1, 2)}
            with self.subTest(mask=mask), patch(
                "jujutui.floating.os.isatty", side_effect=lambda fd: is_tty[fd]
            ), patch(
                "jujutui.floating.os.fstat",
                side_effect=lambda fd: type(
                    "Stat", (), {"st_mode": stat.S_IFCHR, "st_rdev": 17}
                )(),
            ):
                self.assertEqual(terminal_route(None), "launch")
                expected = "inline" if mask == 7 else "invalid"
                self.assertEqual(terminal_route("1"), expected)
        self.assertEqual(terminal_route("forged"), "invalid")

    def test_terminal_route_rejects_three_distinct_ttys(self) -> None:
        with patch("jujutui.floating.os.isatty", return_value=True), patch(
            "jujutui.floating.os.fstat",
            side_effect=lambda fd: type(
                "Stat", (), {"st_mode": stat.S_IFCHR, "st_rdev": 10 + fd}
            )(),
        ):
            self.assertEqual(terminal_route("1"), "invalid")

    def test_partial_tty_subprocess_refuses_rendering_before_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = _make_stow_fake_home(Path(directory))
            master, slave = os.openpty()
            env = {
                "HOME": str(fixture["home"]),
                "XDG_RUNTIME_DIR": str(fixture["runtime"]),
                "PATH": f"{fixture['bin']}:/usr/bin:/bin",
                "TERM": "xterm-256color",
                "LANG": "C.UTF-8",
                FOOT_TTY_MARKER: "1",
            }
            try:
                result = subprocess.run(
                    [str(fixture["launcher_bin"] / "bw-card"), "item_1"],
                    stdin=slave,
                    stdout=slave,
                    stderr=subprocess.PIPE,
                    env=env,
                    timeout=4,
                    check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertEqual(
                    result.stderr,
                    b"Bitwarden card requires its dedicated Foot terminal.\n",
                )
                os.close(slave)
                slave = -1
                captured = bytearray()
                while select.select([master], [], [], 0.05)[0]:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    captured.extend(chunk)
                self.assertNotIn(b"Example <item>", captured)
            finally:
                if slave >= 0:
                    os.close(slave)
                os.close(master)

    def test_source_only_backend_import_is_in_session_adapter_or_supervisor(self) -> None:
        allowed = {"session.py", "clipboard_supervisor.py"}
        for source in Path("tui/.local/lib/jujutui").glob("*.py"):
            if source.name in allowed:
                continue
            contents = source.read_text(encoding="utf-8")
            self.assertNotIn("import bwsession", contents, source.name)
            self.assertNotIn("from bwsession", contents, source.name)

    def test_fake_unlock_api_matches_w_public_signatures(self) -> None:
        import ast

        w_source = Path("bitwarden/.local/lib/bwsession/__init__.py")
        fake_source = Path("tui/tests/fakes/bwsession.py")

        def public_shapes(path: Path) -> dict[str, tuple[tuple[str, ...], tuple[str, ...]]]:
            tree = ast.parse(path.read_text(encoding="utf-8"))
            result = {}
            for node in tree.body:
                if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    continue
                if node.name not in {"unlock", "unlock_ticket", "lock_generation"}:
                    continue
                args = node.args.args
                defaults = tuple(ast.unparse(value) for value in node.args.defaults)
                result[node.name] = (tuple(arg.arg for arg in args), defaults)
            return result

        self.assertEqual(public_shapes(fake_source), public_shapes(w_source))

    def test_cancelled_unlock_ticket_never_enters_backend(self) -> None:
        from jujutui import session

        ticket = session.unlock_ticket()
        bwsession.cancel_unlocks()
        cancel_event = threading.Event()
        cancel_event.set()
        with self.assertRaises(SessionCancelled):
            session.unlock_session(
                b"synthetic-password",
                ticket,
                cancel_event=cancel_event,
            )
        self.assertFalse(any(call[0] == "unlock" for call in bwsession.CALLS))

    def test_textual_exception_handler_exits_with_fixed_message(self) -> None:
        from jujutui.base import create_card_app_class

        CardApp, _widgets = create_card_app_class()
        app = CardApp()
        with patch("jujutui.base.kill_owned_clipboards") as cleanup, patch.object(
            app, "exit"
        ) as exit_app:
            app._handle_exception(RuntimeError("synthetic private exception"))
        cleanup.assert_called_once_with()
        exit_app.assert_called_once_with(
            return_code=1,
            message="Unable to complete this action.",
        )

    def test_base_exposes_reusable_edge_to_edge_widgets(self) -> None:
        from jujutui.base import create_card_app_class

        with patch.dict(os.environ, {"NO_COLOR": "1"}):
            CardApp, widgets = create_card_app_class()
            self.assertNotIn("NO_COLOR", os.environ)
        for name in ("Header", "FieldRow", "ButtonBar", "HintBar", "StatusLine"):
            self.assertIn(name, widgets)
        self.assertIn("width: 100%;", CardApp.CSS)
        card_css = CardApp.CSS.split("#card {", 1)[1].split("}", 1)[0]
        self.assertNotIn("border:", card_css)
        self.assertNotIn("max-width", card_css)

    def test_password_input_blocks_copy_and_cut_bindings(self) -> None:
        from jujutui.base import create_card_app_class

        CardApp, widgets = create_card_app_class()
        password_input = widgets["PasswordInput"]()
        bindings = {binding.key: binding.action for binding in password_input.BINDINGS}
        self.assertEqual(bindings["ctrl+x"], "deny_clipboard")
        self.assertEqual(bindings["ctrl+c,super+c"], "deny_clipboard")
        self.assertIsNone(password_input.action_copy())
        self.assertIsNone(password_input.action_cut())
        app = CardApp()
        clipboard_before = getattr(app, "_clipboard", None)
        self.assertIsNone(app.copy_to_clipboard("synthetic-password"))
        self.assertEqual(getattr(app, "_clipboard", None), clipboard_before)

    def test_password_display_mask_is_fixed_length(self) -> None:
        from jujutui.bw_card import _PASSWORD_MASK

        self.assertEqual(_PASSWORD_MASK, "••••••••")
        self.assertEqual(len(_PASSWORD_MASK), 8)

    def test_item_card_binds_copy_mnemonics_and_close_keys(self) -> None:
        captured = {}

        def capture_app(app):
            captured["app"] = app
            return 0

        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.terminal_route", return_value="inline"
        ), patch("jujutui.bw_card._run", side_effect=capture_app
        ):
            self.assertEqual(
                bw_card_main(["item_1", "--generation", "a1b2c3d4"]), 0
            )

        bindings = {binding.key: binding.action for binding in captured["app"].BINDINGS}
        self.assertEqual(bindings["u"], "copy_username")
        self.assertEqual(bindings["p"], "copy_password")
        self.assertEqual(bindings["escape"], "close")
        self.assertEqual(bindings["q"], "close")
        self.assertEqual(bindings["ctrl+q"], "close")

    def test_later_generation_mismatch_closes_item_card(self) -> None:
        captured = {}

        def capture_app(app):
            captured["app"] = app
            return 0

        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.terminal_route", return_value="inline"
        ), patch("jujutui.bw_card._run", side_effect=capture_app):
            self.assertEqual(bw_card_main(["item_1"]), 0)

        app = captured["app"]
        app._card_dismissing = False
        app._status_worker = None
        app._copy_worker = None
        app._copy_cancel = None
        bwsession.GENERATION = "deadbeef"
        outcome = app._copy_in_thread("password", True, threading.Event())
        self.assertEqual(outcome, "locked")
        with patch.object(app, "action_close") as close:
            app._copy_finished(outcome)
        close.assert_called_once_with()

    def test_clipboard_copy_requires_generation_binding(self) -> None:
        parameter = inspect.signature(copy).parameters["expected_generation"]
        self.assertEqual(parameter.kind, inspect.Parameter.KEYWORD_ONLY)
        self.assertIs(parameter.default, inspect.Parameter.empty)

    def test_unlock_card_exit_contract_documents_duplicate_status(self) -> None:
        from jujutui import bw_unlock_card

        documentation = " ".join(inspect.getdoc(bw_unlock_card).split())
        self.assertIn("3 means the user canceled", documentation)
        self.assertIn("4 means another unlock card is already running", documentation)

    def test_ttl_parser_treats_config_as_data(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "bw-session.conf"
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": temp}):
                path.write_text("TTL_HOURS=12\n", encoding="utf-8")
                self.assertEqual(configured_ttl_hours(), 12)
                path.write_text("TTL_HOURS=$(touch /tmp/not-run)\n", encoding="utf-8")
                self.assertIsNone(configured_ttl_hours())
                self.assertFalse(Path("/tmp/not-run").exists())

    def test_unlock_session_row_does_not_repeat_its_label(self) -> None:
        from jujutui.bw_unlock_card import _ttl_label

        with patch("jujutui.config.configured_ttl_hours", return_value=8):
            self.assertEqual(
                _ttl_label(),
                "Expires after up to 8 hours; use does not renew the deadline.",
            )

    def test_real_headless_launchers_use_fake_backend_and_propagate_exit_codes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = _make_stow_fake_home(Path(directory))
            common = {
                "HOME": str(fixture["home"]),
                "XDG_RUNTIME_DIR": str(fixture["runtime"]),
                "PATH": f"{fixture['bin']}:/usr/bin:/bin",
                "TERM": "xterm-256color",
                "LANG": "C.UTF-8",
            }
            item_env = common | {"FAKE_FOOT_INPUT_1": "q"}
            started = time.monotonic()
            item = subprocess.run(
                [str(fixture["launcher_bin"] / "bw-card"), "item_1"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=item_env,
                timeout=6,
                check=False,
            )
            self.assertEqual(item.returncode, 0, item.stderr)
            self.assertEqual(item.stdout, b"")
            self.assertEqual(item.stderr, b"")

            cancel_env = common | {"FAKE_FOOT_INPUT_1": "\x1b"}
            first_unlock = subprocess.run(
                [str(fixture["launcher_bin"] / "bw-unlock-card")],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=cancel_env,
                timeout=6,
                check=False,
            )
            self.assertEqual(first_unlock.returncode, 3, first_unlock.stderr)
            second_unlock = subprocess.run(
                [str(fixture["launcher_bin"] / "bw-unlock-card")],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=cancel_env,
                timeout=6,
                check=False,
            )
            self.assertEqual(second_unlock.returncode, 3, second_unlock.stderr)
            self.assertEqual(first_unlock.stdout + first_unlock.stderr, b"")
            self.assertEqual(second_unlock.stdout + second_unlock.stderr, b"")

            revoke_log = fixture["home"] / "generation-revoked"
            commit_then_cancel = common | {
                "FAKE_FOOT_INPUT_1": "test-password\r",
                "FAKE_FOOT_INPUT_2": "\x1b",
                "FAKE_FOOT_SECOND_DELAY": "1.2",
                "FAKE_UNLOCK_HANG": "1",
                "FAKE_UNLOCK_COMMIT_BEFORE_CANCEL": "1",
                "FAKE_LOCK_GENERATION_LOG": str(revoke_log),
            }
            abandoned_unlock = subprocess.run(
                [str(fixture["launcher_bin"] / "bw-unlock-card")],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=commit_then_cancel,
                timeout=8,
                check=False,
            )
            self.assertEqual(abandoned_unlock.returncode, 3, abandoned_unlock.stderr)
            self.assertEqual(revoke_log.read_text(encoding="utf-8"), "c0ffee12\n")
            self.assertEqual(abandoned_unlock.stdout + abandoned_unlock.stderr, b"")
            self.assertLess(time.monotonic() - started, 6.0)

    def test_stuck_item_worker_cannot_hold_launcher_process_open(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = _make_stow_fake_home(Path(directory))
            capture = fixture["home"] / "pty-output"
            env = {
                "HOME": str(fixture["home"]),
                "XDG_RUNTIME_DIR": str(fixture["runtime"]),
                "PATH": f"{fixture['bin']}:/usr/bin:/bin",
                "TERM": "xterm-256color",
                "LANG": "C.UTF-8",
                "FAKE_FOOT_INPUT_1": "p",
                "FAKE_FOOT_INPUT_2": "q",
                "FAKE_FOOT_SECOND_DELAY": "1.2",
                "FAKE_SECRET_HANG": "1",
                "FAKE_FOOT_CAPTURE_PATH": str(capture),
            }
            started = time.monotonic()
            result = subprocess.run(
                [str(fixture["launcher_bin"] / "bw-card"), "item_1"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
                timeout=4,
                check=False,
            )
            output = capture.read_bytes() if capture.exists() else b""
            self.assertEqual(
                result.returncode,
                1,
                result.stderr + output[-300:],
            )
            self.assertLess(time.monotonic() - started, 3.0)
            self.assertEqual(result.stdout + result.stderr, b"")
            self.assertIn(b"Bitwarden card stopped a pending backend call.", output)

    def _make_item_app(self):
        captured = {}

        def capture_app(app):
            captured["app"] = app
            return 0

        with patch("jujutui.bw_card.apply_process_hardening"), patch(
            "jujutui.bw_card.terminal_route", return_value="inline"
        ), patch("jujutui.bw_card._run", side_effect=capture_app):
            self.assertEqual(bw_card_main(["item_1"]), 0)
        return captured["app"]

    def _make_unlock_app(self):
        captured = {}
        lock_fd = os.open(os.devnull, os.O_RDONLY)

        def capture_app(app):
            captured["app"] = app
            return 0

        with patch("jujutui.bw_unlock_card.apply_process_hardening"), patch(
            "jujutui.bw_unlock_card.terminal_route", return_value="inline"
        ), patch("jujutui.instance.acquire_unlock_card_lock", return_value=lock_fd), patch(
            "jujutui.bw_unlock_card._run", side_effect=capture_app
        ):
            self.assertEqual(bw_unlock_card_main([]), 0)
        return captured["app"]

    def test_item_escape_q_and_close_stop_real_textual_loop(self) -> None:
        async def exercise() -> None:
            for dismissal in ("escape", "q", "button"):
                app = self._make_item_app()
                async with app.run_test() as pilot:
                    if dismissal == "button":
                        await pilot.click("#close")
                    else:
                        await pilot.press(dismissal)
                    self.assertTrue(
                        await _wait_for(lambda: not app.is_running), dismissal
                    )

            app = self._make_item_app()
            app._inactivity_timeout = 5
            async with app.run_test():
                self.assertTrue(
                    await _wait_for(lambda: not app.is_running, timeout=6.0),
                    "inactivity",
                )

        asyncio.run(exercise())

    def test_item_lock_and_generation_changes_stop_real_textual_loop(self) -> None:
        async def exercise() -> None:
            for change in ("lock", "generation"):
                bwsession.STATE = "unlocked"
                bwsession.GENERATION = "a1b2c3d4"
                app = self._make_item_app()
                async with app.run_test():
                    if change == "lock":
                        bwsession.STATE = "locked"
                    else:
                        bwsession.GENERATION = "deadbeef"
                    app._check_session()
                    self.assertTrue(
                        await _wait_for(lambda: not app.is_running), change
                    )

        asyncio.run(exercise())

    def test_item_worker_state_is_initialized_before_mount(self) -> None:
        app = self._make_item_app()
        self.assertFalse(app._status_busy)
        self.assertEqual(app._status_busy_polls, 0)
        self.assertIsNone(app._status_worker)
        self.assertIsNone(app._status_cancel)
        self.assertIsNone(app._session_timer)
        self.assertFalse(app._copy_busy)
        self.assertIsNone(app._copy_worker)
        self.assertIsNone(app._copy_cancel)
        self.assertFalse(app._last_copy_sensitive)

    def test_unlock_escape_q_close_inactivity_and_desktop_lock_stop_real_loop(self) -> None:
        async def exercise() -> None:
            for dismissal in ("escape", "q", "button", "desktop"):
                bwsession.DESKTOP_UNLOCKED = True
                app = self._make_unlock_app()
                async with app.run_test() as pilot:
                    if dismissal == "button":
                        await pilot.click("#close")
                    elif dismissal == "desktop":
                        bwsession.DESKTOP_UNLOCKED = False
                        app._check_desktop()
                    else:
                        await pilot.press(dismissal)
                    self.assertTrue(
                        await _wait_for(lambda: not app.is_running), dismissal
                    )
                    self.assertEqual(app.return_code, 3)

            bwsession.DESKTOP_UNLOCKED = True
            app = self._make_unlock_app()
            app._inactivity_timeout = 5
            async with app.run_test():
                self.assertTrue(
                    await _wait_for(lambda: not app.is_running, timeout=6.0),
                    "inactivity",
                )
                self.assertEqual(app.return_code, 3)

        asyncio.run(exercise())

    def test_unlock_success_stops_real_textual_loop_with_zero(self) -> None:
        async def exercise() -> None:
            bwsession.DESKTOP_UNLOCKED = True
            app = self._make_unlock_app()
            with patch("jujutui.bw_unlock_card._send_success_toast"):
                async with app.run_test():
                    app.query_one("#master-password").value = "test-password"
                    app._unlock()
                    self.assertTrue(
                        await _wait_for(lambda: not app.is_running), "unlock success"
                    )
            self.assertEqual(app.return_code, 0)
            self.assertIn(
                ("unlock", b"test-password", True, bwsession.CANCEL_TOKEN),
                bwsession.CALLS,
            )

        asyncio.run(exercise())

    def test_revocation_failure_stops_real_textual_loop_with_one(self) -> None:
        async def exercise() -> None:
            app = self._make_unlock_app()
            with patch.dict(
                os.environ,
                {
                    "FAKE_UNLOCK_HANG": "1",
                    "FAKE_UNLOCK_COMMIT_BEFORE_CANCEL": "1",
                    "FAKE_LOCK_GENERATION_FAIL": "1",
                },
            ):
                async with app.run_test():
                    app.query_one("#master-password").value = "test-password"
                    app._unlock()
                    self.assertTrue(
                        await _wait_for(
                            lambda: any(
                                call and call[0] == "unlock"
                                for call in bwsession.CALLS
                            ),
                        ),
                        "unlock worker started",
                    )
                    app.action_close()
                    self.assertTrue(
                        await _wait_for(lambda: not app.is_running),
                        "failed generation revocation",
                    )
            self.assertEqual(app.return_code, 1)
            self.assertIn(
                ("lock_generation", "c0ffee12", "manual"), bwsession.CALLS
            )

        asyncio.run(exercise())

    def test_textual_exit_probe_detects_private_closing_flag_regression(self) -> None:
        from jujutui.base import create_card_app_class

        CardApp, _widgets = create_card_app_class()

        class BrokenCard(CardApp):
            def on_mount(self) -> None:
                super().on_mount()
                self.set_timer(0.5, self._break_exit)

            def _break_exit(self) -> None:
                self._closing = True
                self.exit()

        async def exercise() -> None:
            app = BrokenCard()
            async with app.run_test() as pilot:
                await pilot.pause(0.7)
                self.assertTrue(app.is_running)
                self.assertTrue(app._closing)
                # Release the negative-control app through Textual's real public path.
                app._closing = False
                app.exit()
                self.assertTrue(await _wait_for(lambda: not app.is_running))

        asyncio.run(exercise())

    def test_t_card_assigned_fields_do_not_shadow_textual_lifecycle_fields(self) -> None:
        import ast
        from textual.app import App
        from textual.message_pump import MessagePump

        reserved = set(dir(App)) | set(dir(MessagePump)) | set(dir(App()))
        for path in (
            Path("tui/.local/lib/jujutui/base.py"),
            Path("tui/.local/lib/jujutui/bw_card.py"),
            Path("tui/.local/lib/jujutui/bw_unlock_card.py"),
        ):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            assigned = set()
            for node in ast.walk(tree):
                targets = []
                if isinstance(node, ast.Assign):
                    targets = node.targets
                elif isinstance(node, (ast.AnnAssign, ast.AugAssign)):
                    targets = [node.target]
                for target in targets:
                    if (
                        isinstance(target, ast.Attribute)
                        and isinstance(target.value, ast.Name)
                        and target.value.id == "self"
                    ):
                        assigned.add(target.attr)
            self.assertFalse(assigned & reserved, f"{path}: {assigned & reserved}")

    def test_unlock_cancel_failure_can_be_retried_and_exits_event_loop(self) -> None:
        async def exercise() -> None:
            app = self._make_unlock_app()
            started = threading.Event()
            released = threading.Event()
            cancel_calls = 0

            def slow_unlock(_password, desktop=True, ticket=None):
                started.set()
                released.wait(2.0)
                raise bwsession.WrongPassword

            def cancel_unlocks():
                nonlocal cancel_calls
                cancel_calls += 1
                if cancel_calls == 1:
                    raise bwsession.Error("synthetic cancel failure")
                released.set()

            async with app.run_test():
                app.query_one("#master-password").value = "synthetic-password"
                with patch.object(bwsession, "unlock", side_effect=slow_unlock), patch.object(
                    bwsession, "cancel_unlocks", side_effect=cancel_unlocks
                ):
                    app._unlock()
                    self.assertTrue(await _wait_for(started.is_set))
                    with patch.object(
                        app, "_reset_inactivity", wraps=app._reset_inactivity
                    ) as reset_inactivity:
                        app.action_close()
                        reset_inactivity.assert_called_once_with()
                    self.assertTrue(app.is_running)
                    self.assertFalse(app._card_dismissing)
                    self.assertTrue(app._dismiss_requested is False)
                    app.action_close()
                    self.assertTrue(await _wait_for(lambda: not app.is_running))
                    self.assertEqual(app.return_code, 3)
            self.assertEqual(cancel_calls, 2)

        asyncio.run(exercise())

    def test_close_before_unlock_enters_backend_prevents_unlock_call(self) -> None:
        from jujutui import session

        async def exercise() -> None:
            app = self._make_unlock_app()
            acquired = threading.Event()
            release = threading.Event()
            real_run_backend_worker = app.run_backend_worker

            def hold_t_lock() -> None:
                session._BACKEND_LOCK.acquire()
                acquired.set()
                release.wait(2.0)
                session._BACKEND_LOCK.release()

            def start_worker_behind_lock(function, *args, **kwargs):
                holder.start()
                if not acquired.wait(1.0):
                    raise AssertionError("test failed to hold T backend lock")
                return real_run_backend_worker(function, *args, **kwargs)

            holder = threading.Thread(target=hold_t_lock, daemon=True)
            try:
                async with app.run_test():
                    app.query_one("#master-password").value = "synthetic-password"
                    with patch.object(
                        app, "run_backend_worker", side_effect=start_worker_behind_lock
                    ), patch.object(bwsession, "unlock") as unlock:
                        app._unlock()
                        app.action_close()
                        self.assertTrue(
                            await _wait_for(lambda: not app.is_running)
                        )
                        release.set()
                        holder.join(timeout=1.0)
                        self.assertFalse(holder.is_alive())
                        self.assertFalse(unlock.called)
                        self.assertEqual(app.return_code, 3)
            finally:
                release.set()
                if holder.ident is not None:
                    holder.join(timeout=1.0)

        asyncio.run(exercise())

    def test_status_busy_skips_one_poll_then_fails_closed(self) -> None:
        from jujutui import session

        async def exercise() -> None:
            app = self._make_item_app()
            acquired = threading.Event()
            release = threading.Event()

            def hold_t_lock() -> None:
                session._BACKEND_LOCK.acquire()
                acquired.set()
                release.wait(2.0)
                session._BACKEND_LOCK.release()

            holder = threading.Thread(target=hold_t_lock, daemon=True)
            holder.start()
            self.assertTrue(acquired.wait(1.0))
            try:
                with patch("jujutui.session.BACKEND_LOCK_WAIT_SECONDS", 0.04):
                    async with app.run_test():
                        app._check_session()
                        self.assertTrue(
                            await _wait_for(lambda: app._status_busy_polls == 1)
                        )
                        self.assertTrue(app.is_running)
                        app._check_session()
                        self.assertTrue(
                            await _wait_for(lambda: not app.is_running)
                        )
            finally:
                release.set()
                holder.join(timeout=1.0)

        asyncio.run(exercise())

    def test_bwsession_calls_are_serialized_in_real_workers_and_detector_has_negative_control(self) -> None:
        from jujutui import session

        class NoopLock:
            def acquire(self, timeout=None):
                return True

            def release(self):
                return None

        async def exercise(disable_t_lock: bool) -> bool:
            app = self._make_item_app()
            bwsession.reset_metrics()
            bwsession.BLOCK_METHOD = "status"
            lock_patch = patch("jujutui.session._BACKEND_LOCK", NoopLock()) if disable_t_lock else patch(
                "jujutui.session._BACKEND_LOCK", session._BACKEND_LOCK
            )
            async with app.run_test():
                with lock_patch, patch("jujutui.bw_card.copy", return_value=None):
                    app._check_session()
                    self.assertTrue(await _wait_for(bwsession.BLOCK_STARTED.is_set))
                    app.action_copy_password()
                    if disable_t_lock:
                        self.assertTrue(await _wait_for(bwsession.OVERLAP.is_set))
                    else:
                        await asyncio.sleep(0.12)
                        self.assertFalse(bwsession.OVERLAP.is_set())
                        self.assertEqual(bwsession.MAX_ACTIVE_CALLS, 1)
                    bwsession.BLOCK_RELEASE.set()
                    self.assertTrue(
                        await _wait_for(
                            lambda: not app._status_busy and not app._copy_busy,
                            timeout=2.0,
                        )
                    )
                    app.action_close()
                    self.assertTrue(await _wait_for(lambda: not app.is_running))
            return bwsession.OVERLAP.is_set()

        self.assertFalse(asyncio.run(exercise(False)))
        self.assertTrue(asyncio.run(exercise(True)))


if __name__ == "__main__":
    unittest.main()

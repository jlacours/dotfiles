#!/usr/bin/env python3
"""Synthetic /proc tests; never read live argv or depend on running apps."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "quickshell/.config/quickshell/hyprbar/window_apps.py"
spec = importlib.util.spec_from_file_location("window_apps", MODULE)
apps = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = apps
spec.loader.exec_module(apps)


class ForegroundTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.proc = Path(self.temp.name)
        self.add(10, "foot", 1, 10, 1, 0, -1)
        (self.proc / "10/exe").symlink_to("/usr/bin/foot")
        self.add(20, "zsh", 10, 20, 20, 123, 30)

    def add(self, pid, name, parent, group, session, tty, fg, argv=None, start=100):
        directory = self.proc / str(pid)
        directory.mkdir(exist_ok=True)
        fields = ["S", str(parent), str(group), str(session), str(tty), str(fg)] + ["0"] * 13 + [str(start)]
        (directory / "stat").write_text(f"{pid} ({name}) " + " ".join(fields))
        (directory / "cmdline").write_bytes(b"\0".join(value.encode() for value in (argv or [name])) + b"\0")

    def kind(self):
        return apps.collect([10], self.proc)["10"]["kind"]

    def test_foreground_apps_and_background_decoy(self):
        self.add(40, "codex", 20, 40, 20, 123, 30)
        for command in ["nvim", "emacs", "emacsclient", "claude", "codex", "hermes", "pi"]:
            with self.subTest(command=command):
                self.add(30, command, 20, 30, 20, 123, 30)
                self.assertEqual(self.kind(), command)

    def test_shell_and_unknown(self):
        self.add(20, "zsh", 10, 20, 20, 123, 20)
        self.assertEqual(self.kind(), "shell")
        self.add(20, "curl", 10, 20, 20, 123, 20, ["curl", "https://codex.example/nvim"])
        self.assertEqual(self.kind(), "terminal")

    def test_herdr_inner_ptys_do_not_become_window_apps(self):
        self.add(30, "herdr", 20, 30, 20, 123, 30)
        self.add(40, "zsh", 30, 40, 40, 456, 50)
        self.add(50, "codex", 40, 50, 40, 456, 50)
        self.assertEqual(self.kind(), "herdr")

    def test_interpreter_script_identity(self):
        self.assertEqual(apps.command_kind("node", ["node", "/opt/pi-coding-agent/dist/cli.js"]), "pi")
        self.assertEqual(apps.command_kind("node", ["node", "unrelated.js", "codex"]), "terminal")
        self.assertEqual(apps.command_kind("python3", ["python3", "-m", "hermes_cli.main"]), "hermes")

    def test_hermes_inline_launcher_is_structural(self):
        code = "from hermes_cli.main import main\nsys.exit(main())"
        self.assertEqual(apps.command_kind("python3", ["python3", "-I", "-c", code]), "hermes")
        self.assertEqual(apps.command_kind("python3", ["python3", "-I", "-c", code, "--run-module", "other"]), "terminal")
        self.assertEqual(apps.command_kind("python3", ["python3", "-c", "print('hermes_cli.main')"]), "terminal")

    def test_ambiguous_server_and_pipeline(self):
        self.add(30, "claude", 20, 30, 20, 123, 30)
        self.add(31, "codex", 20, 30, 20, 123, 30)
        self.assertEqual(self.kind(), "terminal")
        self.add(60, "zsh", 10, 60, 60, 789, 60)
        self.assertEqual(self.kind(), "terminal")

    def test_stat_comm_parentheses_and_spaces(self):
        self.add(30, "odd (app) name", 20, 30, 20, 123, 30)
        proc = apps.read_stat(self.proc / "30/stat")
        self.assertEqual(proc.comm, "odd (app) name")
        self.assertEqual(proc.start, 100)
        self.assertEqual(self.kind(), "terminal")

    def test_exit_and_pid_reuse(self):
        self.add(30, "codex", 20, 30, 20, 123, 30)
        procs = apps.snapshot(self.proc)
        (self.proc / "30/stat").unlink()
        self.assertEqual(apps.foreground_app(10, procs, self.proc)["kind"], "terminal")
        self.add(30, "codex", 20, 30, 20, 123, 30, start=101)
        self.assertEqual(apps.foreground_app(10, procs, self.proc)["kind"], "terminal")

    def test_foreground_switch_during_sample(self):
        self.add(30, "codex", 20, 30, 20, 123, 30)
        procs = apps.snapshot(self.proc)
        original = apps.read_stat
        def switched(path):
            if path == self.proc / "20/stat":
                self.add(20, "zsh", 10, 20, 20, 123, 20)
            return original(path)
        with patch.object(apps, "read_stat", side_effect=switched):
            self.assertEqual(apps.foreground_app(10, procs, self.proc)["kind"], "terminal")


if __name__ == "__main__":
    unittest.main()

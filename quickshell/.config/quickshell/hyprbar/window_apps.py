#!/usr/bin/env python3
"""Read-only Foot foreground collector. No titles, environment or full argv output."""

import ast
import json
import os
from pathlib import Path
import sys
import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Proc:
    pid: int
    comm: str
    ppid: int
    pgrp: int
    session: int
    tty: int
    foreground: int
    start: int


def read_stat(path):
    try:
        text = path.read_text()
        left, right = text.index("("), text.rindex(")")
        fields = text[right + 2:].split()
        return Proc(int(text[:left]), text[left + 1:right], int(fields[1]),
                    int(fields[2]), int(fields[3]), int(fields[4]),
                    int(fields[5]), int(fields[19]))
    except (OSError, ValueError, IndexError):
        return None


APPS = {"nvim": "Neovim", "vim": "Vim", "emacs": "Emacs",
        "emacsclient": "Emacs", "claude": "Claude", "codex": "Codex",
        "hermes": "Hermes", "pi": "Pi",
        "herdr": "Herdr"}
SHELLS = {"zsh", "bash", "fish", "sh", "dash", "nu"}
SCRIPTS = {"pi.js": "pi", "hermes.py": "hermes", "hermes_cli.py": "hermes",
           "claude.js": "claude", "codex.js": "codex"}


def command_kind(comm, argv):
    """Recognize command identity only; never search argument/title substrings."""
    name = Path(argv[0]).name if argv else comm
    name = name.lstrip("-")
    if name in APPS or name in SHELLS:
        return "shell" if name in SHELLS else name
    # Only the interpreter's script/module position can identify an app.
    if name in {"node", "nodejs", "python"} or re.fullmatch(r"python3(?:\.\d+)?", name):
        args = argv[1:]
        while args and args[0] in {"-I", "-u", "-B", "-s", "-S", "-E"}:
            args = args[1:]
        if args and not args[0].startswith("-"):
            script = Path(args[0]).name
            if script in APPS:
                return script
            if script in SCRIPTS:
                return SCRIPTS[script]
            if script == "cli.js" and "pi-coding-agent" in Path(args[0]).parts:
                return "pi"
        if len(args) > 1 and args[0] == "-m" and args[1] in {"hermes_cli", "hermes_cli.main"}:
            return "hermes"
        # This machine's Hermes launcher uses Python -I -c, rather than a
        # script. Parse its entry point structurally, never grep prompt text.
        if name.startswith("python") and len(args) > 1 and args[0] == "-c" and args[2:3] != ["--run-module"]:
            try:
                statements = ast.parse(args[1]).body
                imports_main = any(isinstance(node, ast.ImportFrom) and node.module == "hermes_cli.main"
                                   and any(alias.name == "main" and alias.asname is None for alias in node.names)
                                   for node in statements)
                invokes_main = any(isinstance(node, ast.Expr)
                                   and ast.dump(node.value) == ast.dump(ast.parse("sys.exit(main())").body[0].value)
                                   for node in statements)
                if imports_main and invokes_main:
                    return "hermes"
            except (SyntaxError, ValueError, RecursionError):
                pass
    return "terminal"


def snapshot(proc_root):
    result = {}
    for entry in proc_root.iterdir():
        if entry.name.isdecimal():
            proc = read_stat(entry / "stat")
            if proc:
                result[proc.pid] = proc
    return result


def foreground_app(pid, procs, proc_root):
    root = procs.get(pid)
    if root is None:
        return None
    directory = proc_root / str(pid)
    try:
        if Path(os.readlink(directory / "exe")).name != "foot":
            return None
    except OSError:
        return None
    fallback = {"kind": "terminal", "label": "Foot · foreground unavailable"}
    children = {}
    for proc in procs.values():
        children.setdefault(proc.ppid, []).append(proc)
    # The first controlling TTY below Foot belongs to the outer terminal.
    # Stop there: Herdr/tmux's inner PTYs do not establish an active pane.
    anchors, pending, visited = [], list(children.get(pid, [])), set()
    while pending and len(visited) < 512:
        proc = pending.pop()
        if proc.pid in visited:
            continue
        visited.add(proc.pid)
        if proc.tty:
            anchors.append(proc)
        else:
            pending.extend(children.get(proc.pid, []))
    if pending or len(anchors) != 1:
        return fallback  # foot-server with several windows is ambiguous.
    anchor = anchors[0]
    if anchor.foreground <= 0:
        return fallback
    # Restrict to the terminal's descendants and controlling session/TTY.
    descendants, pending = {}, [anchor]
    while pending and len(descendants) < 512:
        proc = pending.pop()
        if proc.pid in descendants:
            continue
        descendants[proc.pid] = proc
        pending.extend(children.get(proc.pid, []))
    if pending:
        return fallback
    group = [proc for proc in descendants.values()
             if proc.tty == anchor.tty and proc.session == anchor.session
             and proc.pgrp == anchor.foreground]
    # Prefer the job leader, then a stable PID order (pipelines are ambiguous).
    group.sort(key=lambda proc: (proc.pid != anchor.foreground, proc.pid))
    kinds = []
    for proc in group:
        try:
            # Bounded read; argv stays private and never enters JSON or logs.
            with (proc_root / str(proc.pid) / "cmdline").open("rb") as stream:
                argv = [part.decode(errors="replace") for part in stream.read(16384).split(b"\0") if part]
            if read_stat(proc_root / str(proc.pid) / "stat") != proc:
                return fallback
            kinds.append(command_kind(proc.comm, argv))
        except OSError:
            return fallback
    # Recheck job ownership after reading commands: exit/PID reuse/job switches
    # invalidate the entire sample rather than leaving a stale recognized app.
    if read_stat(directory / "stat") != root or read_stat(proc_root / str(anchor.pid) / "stat") != anchor:
        return fallback
    if not kinds:
        return fallback
    recognized = set(kinds) - {"terminal", "shell"}
    if len(recognized) > 1:
        return {"kind": "terminal", "label": "Foot · foreground pipeline"}
    kind = next(iter(recognized)) if recognized else kinds[0]
    label = "Shell" if kind == "shell" else APPS.get(kind, "Terminal")
    return {"kind": kind, "label": label}


def collect(pids, proc_root=Path("/proc")):
    procs = snapshot(proc_root)
    result = {}
    for pid in set(pids):
        app = foreground_app(pid, procs, proc_root)
        if app:
            result[str(pid)] = app
    return result


if __name__ == "__main__":
    pids = [int(value) for value in sys.argv[1:257] if value.isdecimal()]
    print(json.dumps(collect(pids), separators=(",", ":")))

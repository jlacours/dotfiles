"""Launch a command in a dedicated, non-recording Foot window."""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
from collections.abc import Sequence


class FloatingLaunchError(RuntimeError):
    """A fixed, sanitized launch failure."""


FOOT_TTY_MARKER = "JUJUTUI_CARD_FOOT_TTY"


def terminal_route(marker: str | None) -> str:
    """Route to Foot or verify shared TTYs; marker is not same-user authentication.

    A same-user process can deliberately set the marker. It only avoids the
    dedicated Foot wrapper; redirected streams are still rejected below.
    """
    if marker is None:
        return "launch"
    if marker != "1":
        return "invalid"
    devices: list[int] = []
    try:
        for fd in (0, 1, 2):
            if not os.isatty(fd):
                return "invalid"
            info = os.fstat(fd)
            if not stat.S_ISCHR(info.st_mode):
                return "invalid"
            devices.append(info.st_rdev)
    except OSError:
        return "invalid"
    return "inline" if len(set(devices)) == 1 else "invalid"


def launch_floating(
    argv: Sequence[str], *, wait: bool = False
) -> subprocess.Popen[bytes] | int:
    """Start Foot safely, optionally returning the command's exit status."""
    if isinstance(argv, (str, bytes)) or not argv or any(
        not isinstance(arg, str) or "\0" in arg for arg in argv
    ):
        raise FloatingLaunchError
    foot = shutil.which("foot")
    if foot is None:
        raise FloatingLaunchError

    command = [
        foot,
        "--app-id=jujutui-card",
        "--title=Bitwarden",
        "-o",
        "scrollback.lines=0",
        "-o",
        "security.osc52=disabled",
        "-o",
        "selection-target=none",
        "-o",
        "locked-title=yes",
        "--",
        *argv,
    ]
    child_env = os.environ.copy()
    child_env.pop("BW_SESSION", None)
    child_env["BW_NOINTERACTION"] = "true"
    child_env[FOOT_TTY_MARKER] = "1"
    for name in tuple(child_env):
        if name.startswith(("TEXTUAL_", "PYTHON")):
            child_env.pop(name, None)
    try:
        if wait:
            return subprocess.run(
                command,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=child_env,
                close_fds=True,
                check=False,
            ).returncode
        return subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=child_env,
            close_fds=True,
            start_new_session=True,
        )
    except (OSError, ValueError) as exc:
        raise FloatingLaunchError from exc

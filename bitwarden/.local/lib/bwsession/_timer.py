"""Transient systemd user timers that expire one session generation."""

import os
import re
import subprocess

UNIT_PREFIX = "bwsession-expire-"
_GENERATION = re.compile(r"^[0-9a-f]{8}$")


def bw_session_path():
    return os.path.join(os.path.expanduser("~"), ".local", "bin", "bw-session")


def unit_name(generation):
    if not _GENERATION.match(generation or ""):
        raise ValueError("bad generation")
    return f"{UNIT_PREFIX}{generation}"


def _systemctl(*args, timeout=10):
    try:
        return subprocess.run(
            ["systemctl", "--user", *args],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=timeout, check=False).returncode
    except (OSError, subprocess.TimeoutExpired):
        return 255


class SystemdTimers:
    """Arm/disarm `bwsession-expire-<generation>.timer` (no secrets in argv)."""

    def is_armed(self, generation, timeout=10):
        return _systemctl("is-active", "--quiet", unit_name(generation) + ".timer",
                          timeout=timeout) == 0

    def arm(self, generation, deadline, timeout=15):
        unit = unit_name(generation)
        if self.is_armed(generation):
            return True
        # A previous failed attempt can leave the name loaded; clear it first.
        _systemctl("reset-failed", unit + ".timer", unit + ".service")
        try:
            rc = subprocess.run(
                [
                    "systemd-run", "--user", "--quiet", "--collect",
                    f"--unit={unit}",
                    "--description=Bitwarden session expiry",
                    f"--on-calendar=@{int(deadline)}",
                    "--timer-property=AccuracySec=1s",
                    "--property=Type=oneshot",
                    "--",
                    bw_session_path(), "_expire", generation,
                ],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=timeout, check=False).returncode
        except (OSError, subprocess.TimeoutExpired):
            return False
        return rc == 0 and self.is_armed(generation)

    def disarm(self, generation, timeout=10):
        try:
            unit = unit_name(generation)
        except ValueError:
            return
        _systemctl("stop", unit + ".timer", timeout=timeout)


class FakeTimers:
    def __init__(self):
        self.armed = {}
        self.fail = False

    def is_armed(self, generation, timeout=None):
        return generation in self.armed

    def arm(self, generation, deadline, timeout=None):
        if self.fail:
            return False
        self.armed[generation] = deadline
        return True

    def disarm(self, generation, timeout=None):
        self.armed.pop(generation, None)

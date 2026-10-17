"""~/.config/bw-session.conf: KEY=VALUE data, parsed with bounds, never sourced."""

import os
from dataclasses import dataclass

MAX_CONFIG_BYTES = 8192


@dataclass(frozen=True)
class Config:
    ttl_hours: int = 8
    lock_on_suspend: bool = True
    lock_on_screenlock: bool = False
    idle_lock_min: int = 0
    remind: bool = True

    @property
    def ttl_seconds(self):
        return self.ttl_hours * 3600


def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "bw-session.conf")


def _int(value, low, high, default):
    if not value.isascii() or not value.isdigit() or len(value) > 5:
        return default
    number = int(value)
    return number if low <= number <= high else default


def _bool(value, default):
    lowered = value.lower()
    if lowered in ("yes", "true", "1", "on"):
        return True
    if lowered in ("no", "false", "0", "off"):
        return False
    return default


def load_config(path=None):
    """Return a Config; unknown keys and invalid values fall back to defaults."""
    defaults = Config()
    values = {}
    try:
        with open(path or config_path(), "rb") as handle:
            raw = handle.read(MAX_CONFIG_BYTES + 1)
    except OSError:
        return defaults
    if len(raw) > MAX_CONFIG_BYTES:
        return defaults
    for line in raw.decode("utf-8", "replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.strip().strip('"').strip("'")
        values[key.strip()] = value
    return Config(
        ttl_hours=_int(values.get("TTL_HOURS", ""), 1, 24, defaults.ttl_hours),
        lock_on_suspend=_bool(values.get("LOCK_ON_SUSPEND", ""), defaults.lock_on_suspend),
        lock_on_screenlock=_bool(values.get("LOCK_ON_SCREENLOCK", ""), defaults.lock_on_screenlock),
        idle_lock_min=_int(values.get("IDLE_LOCK_MIN", ""), 0, 1440, defaults.idle_lock_min),
        remind=_bool(values.get("REMIND", ""), defaults.remind),
    )

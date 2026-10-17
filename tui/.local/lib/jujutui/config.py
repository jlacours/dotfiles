"""Bounded, non-executing reader for the displayed Bitwarden TTL setting."""

from __future__ import annotations

import os
import re
from pathlib import Path

_TTL_LINE = re.compile(r"\s*TTL_HOURS\s*=\s*([0-9]+)\s*(?:#.*)?\Z")


def configured_ttl_hours() -> int | None:
    """Read only TTL_HOURS as data; never source or evaluate the config file."""
    path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "bw-session.conf"
    try:
        if path.stat().st_size > 16_384:
            return None
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return 8
    except (OSError, UnicodeError):
        return None

    matches: list[str] = []
    for line in lines:
        if "TTL_HOURS" not in line or line.lstrip().startswith("#"):
            continue
        match = _TTL_LINE.fullmatch(line)
        if not match:
            return None
        matches.append(match.group(1))
    if not matches:
        return 8
    if len(matches) != 1:
        return None
    try:
        value = int(matches[0])
    except ValueError:
        return None
    return value if 1 <= value <= 24 else None

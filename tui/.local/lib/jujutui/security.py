"""Process hardening and safe literal display helpers."""

from __future__ import annotations

import ctypes
import json
import os
import re
import resource
import unicodedata
from collections.abc import Mapping
from pathlib import Path


class ProcessHardeningError(RuntimeError):
    """Raised when the secret-handling process cannot disable core dumps."""


def apply_process_hardening() -> None:
    """Disable core dumps for this process before any secret is handled."""
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    except (OSError, ValueError) as exc:
        raise ProcessHardeningError from exc

    try:
        libc = ctypes.CDLL(None, use_errno=True)
        result = libc.prctl(4, 0, 0, 0, 0)  # PR_SET_DUMPABLE = 4 on Linux.
        if result != 0:
            raise ProcessHardeningError
    except (AttributeError, OSError) as exc:
        raise ProcessHardeningError from exc


def clear_textual_debug_environment() -> None:
    """Remove inherited Textual debug, driver, screenshot, and log settings."""
    for name in tuple(os.environ):
        if name.startswith("TEXTUAL_") or name in {
            "PYTHONFAULTHANDLER",
            "PYTHONPROFILEIMPORTTIME",
            "PYTHONTRACEMALLOC",
            "RICH_TRACEBACK",
        }:
            os.environ.pop(name, None)


def sanitize_display(value: object, *, limit: int = 240) -> str:
    """Strip controls and bidi formatting, keeping a bounded single-line label."""
    if not isinstance(value, str):
        return ""
    if not isinstance(limit, int) or isinstance(limit, bool) or not 1 <= limit <= 4096:
        raise ValueError("invalid display limit")

    safe_chars: list[str] = []
    for char in value:
        category = unicodedata.category(char)
        if category in {"Cc", "Cf", "Zl", "Zp"}:
            safe_chars.append(" ")
        else:
            safe_chars.append(char)
    return " ".join("".join(safe_chars).split())[:limit]


def wallust_palette() -> Mapping[str, str]:
    """Return validated colors from pywal/Wallust's generated palette, if present."""
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    palette_path = cache_root / "wal" / "colors.json"
    try:
        if palette_path.stat().st_size > 32_768:
            return {}
        data = json.loads(palette_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}

    valid_color = re.compile(r"#[0-9A-Fa-f]{6}\Z")
    raw = data.get("colors", {})
    special = data.get("special", {})
    if not isinstance(raw, dict):
        raw = {}
    if not isinstance(special, dict):
        special = {}

    found: dict[str, str] = {}
    for name, source in (
        ("background", special.get("background")),
        ("foreground", special.get("foreground")),
        ("accent", raw.get("color4")),
        ("secondary", raw.get("color2")),
        ("error", raw.get("color1")),
    ):
        if isinstance(source, str) and valid_color.fullmatch(source):
            found[name] = source
    return found

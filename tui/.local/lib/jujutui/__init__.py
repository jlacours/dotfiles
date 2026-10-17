"""Small, short-lived Textual cards for the desktop."""

from .clipboard import ClipboardDisabled, ClipboardError, copy, kill_owned_clipboards
from .floating import FloatingLaunchError, launch_floating

__all__ = [
    "ClipboardDisabled",
    "ClipboardError",
    "FloatingLaunchError",
    "copy",
    "kill_owned_clipboards",
    "launch_floating",
]

"""Read Hermes replies aloud through ``~/.local/bin/speak``, toggled per session.

``/speak [on|off|stop|status]`` (bare ``/speak`` toggles). speak pushes its
state to the speakscope overlay, so a spoken reply also shows the tesseract
oscilloscope. Off at every launch. A session is the gateway chat (Matrix room)
or the terminal session; one voice at a time, so a new reply cuts the last one.
"""

from __future__ import annotations

import os
import re
import signal
import subprocess
import threading
from pathlib import Path

_SPEAK = str(Path.home() / ".local/bin/speak")
_USAGE = "Usage: /speak [on|off|stop|status]"

_lock = threading.Lock()
_enabled: set[str] = set()
_current: subprocess.Popen | None = None


def _session_key() -> str:
    """Gateway chat or TUI session key; the classic CLI binds none, so it is one session."""
    try:
        from gateway.session_context import get_session_env

        key = get_session_env("HERMES_SESSION_KEY", "")
    except Exception:
        key = os.environ.get("HERMES_SESSION_KEY", "")
    return key or "local"


def _speakable(text: str) -> str:
    """Markdown reply -> plain sentences: drop code blocks and URLs, keep link and code text."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"^\s*(#{1,6}|>|[-*+]|\d+[.)])\s+", "", text, flags=re.M)
    text = re.sub(r"^\s*\|?\s*:?-{3,}.*$", "", text, flags=re.M)
    text = re.sub(r"[*~]+|(?<!\w)_+|_+(?!\w)", "", text)
    sentences = []
    for line in text.splitlines():
        # Table rows read as lists; every line ends as a sentence so TTS pauses.
        line = ", ".join(cell.strip() for cell in line.split("|") if cell.strip())
        line = re.sub(r"\s+", " ", re.sub(r"[^\w\s.,;:!?'\"()%$€&/+=-]", " ", line)).strip(" ,")
        if line:
            sentences.append(line if line[-1] in ".,;:!?" else line + ".")
    return " ".join(sentences)


def _speak_env() -> dict[str, str]:
    """speak's overlay IPC (`qs ipc`) matches instances by Wayland display, which the
    systemd gateway lacks; point it at this session's compositor socket."""
    env = dict(os.environ)
    runtime = env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    if not env.get("WAYLAND_DISPLAY"):
        sockets = sorted(p.name for p in Path(runtime).glob("wayland-*") if p.is_socket())
        if sockets:
            env["WAYLAND_DISPLAY"] = sockets[0]
    if "UTF-8" not in (env.get("LC_ALL") or env.get("LANG") or "").upper():
        env["LANG"] = "C.UTF-8"
    return env


def _stop_locked() -> None:
    global _current
    if _current is not None and _current.poll() is None:
        try:
            # speak's own group: kills playback too, and its EXIT trap resets the overlay.
            os.killpg(_current.pid, signal.SIGTERM)
        except OSError:
            pass
    _current = None


def _stop() -> None:
    with _lock:
        _stop_locked()


def _say(text: str) -> None:
    global _current
    with _lock:
        _stop_locked()
        try:
            proc = subprocess.Popen([_SPEAK], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, env=_speak_env(), start_new_session=True)
        except OSError:
            return
        _current = proc

    # Feed stdin off-thread: a long reply must never block the turn on a full pipe.
    def feed() -> None:
        try:
            with proc.stdin:
                proc.stdin.write(text.encode())
        except OSError:
            pass

    threading.Thread(target=feed, name="speak-replies", daemon=True).start()


def _on_reply(assistant_response=None, **_kwargs) -> None:
    if not isinstance(assistant_response, str):
        return
    with _lock:
        if _session_key() not in _enabled:
            return
    text = _speakable(assistant_response)
    if text:
        _say(text)


def _command(raw_args: str) -> str:
    arg = (raw_args or "").strip().lower()
    key = _session_key()
    if arg == "stop":
        _stop()
        return "Stopped speaking."
    if arg == "status":
        with _lock:
            return "Speaking replies: " + ("on" if key in _enabled else "off")
    if arg not in ("", "on", "off"):
        return _USAGE
    with _lock:
        on = key not in _enabled if not arg else arg == "on"
        if on:
            _enabled.add(key)
        else:
            _enabled.discard(key)
            _stop_locked()
    return "Speaking replies aloud (speak + speakscope)." if on else "Replies stay silent."


def register(ctx) -> None:
    ctx.register_command("speak", _command, args_hint="[on|off|stop|status]",
                         description="Toggle reading replies aloud through speak (shows the speakscope overlay)")
    ctx.register_hook("post_llm_call", _on_reply)

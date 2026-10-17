"""Owned clipboard providers with a supervising, generation-bound parent."""

from __future__ import annotations

import os
import select
import shutil
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from .session import require_unlocked

MAX_CLIPBOARD_BYTES = 1_048_576
MAX_CLIPBOARD_TTL = 300
# W's bwsession.status() can take 20 seconds in its bounded CLI call.
SUPERVISOR_READY_TIMEOUT = 25.0
# Orchestrator verified against the live wl-paste --watch cliphist store:
# synthetic --sensitive values were omitted while a normal copy was stored.
SENSITIVE_CLIPBOARD_VERIFIED = True


class ClipboardError(RuntimeError):
    """A fixed, sanitized clipboard failure."""


class ClipboardDisabled(ClipboardError):
    """Sensitive copy remains disabled until history exclusion is verified."""


@dataclass
class ClipboardHandle:
    supervisor: subprocess.Popen[bytes]


_OWNED: list[ClipboardHandle] = []
_OWNED_LOCK = threading.Lock()


def _supports_pidfd() -> bool:
    return callable(getattr(os, "pidfd_open", None)) and callable(
        getattr(signal, "pidfd_send_signal", None)
    )


def copy(
    data: bytes,
    sensitive: bool,
    ttl: int = 30,
    *,
    expected_generation: str,
    cancel_event: threading.Event | None = None,
) -> ClipboardHandle:
    """Copy exact bytes; the isolated supervisor owns and expires wl-copy."""
    if not isinstance(data, bytes) or len(data) > MAX_CLIPBOARD_BYTES:
        raise ClipboardError
    if not isinstance(sensitive, bool):
        raise ClipboardError
    if not isinstance(ttl, int) or isinstance(ttl, bool) or not 1 <= ttl <= MAX_CLIPBOARD_TTL:
        raise ClipboardError
    if not isinstance(expected_generation, str) or len(expected_generation) != 8:
        raise ClipboardError
    if cancel_event is not None and cancel_event.is_set():
        raise ClipboardError
    if sensitive and not SENSITIVE_CLIPBOARD_VERIFIED:
        raise ClipboardDisabled
    if not _supports_pidfd():
        raise ClipboardError

    require_unlocked(expected_generation)
    wl_copy = shutil.which("wl-copy")
    if wl_copy is None:
        raise ClipboardError

    ready_read = ready_write = -1
    supervisor: subprocess.Popen[bytes] | None = None
    try:
        ready_read, ready_write = os.pipe()
        os.set_inheritable(ready_write, True)
        supervisor_script = Path(__file__).with_name("clipboard_supervisor.py")
        supervisor_env = _child_environment()
        supervisor = subprocess.Popen(
            [
                sys.executable,
                "-I",
                str(supervisor_script),
                wl_copy,
                expected_generation,
                "1" if sensitive else "0",
                str(ttl),
                str(len(data)),
                str(ready_write),
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=supervisor_env,
            close_fds=True,
            pass_fds=(ready_write,),
            start_new_session=True,
        )
        os.close(ready_write)
        ready_write = -1
        handle = ClipboardHandle(supervisor)
        with _OWNED_LOCK:
            _OWNED[:] = [item for item in _OWNED if item.supervisor.poll() is None]
            _OWNED.append(handle)
        if not _wait_for_supervisor(ready_read, cancel_event=cancel_event):
            raise ClipboardError
        os.close(ready_read)
        ready_read = -1
        if cancel_event is not None and cancel_event.is_set():
            raise ClipboardError
        if supervisor.stdin is None:
            raise ClipboardError
        supervisor.stdin.write(data)
        supervisor.stdin.close()
        return handle
    except Exception as exc:
        if ready_read >= 0:
            os.close(ready_read)
        if ready_write >= 0:
            os.close(ready_write)
        if supervisor is not None:
            if supervisor.stdin is not None and not supervisor.stdin.closed:
                try:
                    supervisor.stdin.close()
                except OSError:
                    pass
            _terminate_process(supervisor)
            with _OWNED_LOCK:
                _OWNED[:] = [item for item in _OWNED if item.supervisor is not supervisor]
        raise ClipboardError from exc


def _child_environment() -> dict[str, str]:
    child_env = os.environ.copy()
    child_env.pop("BW_SESSION", None)
    child_env["BW_NOINTERACTION"] = "true"
    for name in tuple(child_env):
        if name.startswith(("TEXTUAL_", "PYTHON")):
            child_env.pop(name, None)
    runtime_dir = child_env.get("XDG_RUNTIME_DIR")
    if runtime_dir and Path(runtime_dir).is_dir():
        child_env["TMPDIR"] = runtime_dir
    return child_env


def _wait_for_supervisor(
    fd: int,
    *,
    cancel_event: threading.Event | None = None,
) -> bool:
    deadline = time.monotonic() + SUPERVISOR_READY_TIMEOUT
    while True:
        if cancel_event is not None and cancel_event.is_set():
            return False
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        readable, _, _ = select.select(
            [fd], [], [], min(0.1, remaining) if cancel_event is not None else remaining
        )
        if not readable:
            continue
        try:
            return os.read(fd, 1) == b"1"
        except OSError:
            return False


def kill_owned_clipboards() -> None:
    """Stop only the isolated supervisors started by this card process."""
    with _OWNED_LOCK:
        owned, _OWNED[:] = list(_OWNED), []
    for handle in owned:
        _terminate_process(handle.supervisor)


def _terminate_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    try:
        process.terminate()
        process.wait(timeout=0.5)
    except (OSError, subprocess.TimeoutExpired):
        try:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=0.5)
        except (OSError, subprocess.TimeoutExpired):
            pass

#!/usr/bin/python3 -I
"""Isolated owner of one foreground wl-copy provider and its hard TTL."""

from __future__ import annotations

import ctypes
import os
import select
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

_MAX_BYTES = 1_048_576
STATUS_POLL_INTERVAL = 3.0


def _start_time(pid: int) -> int | None:
    try:
        stat_line = Path(f"/proc/{pid}/stat").read_text(encoding="ascii")
        end = stat_line.rfind(")")
        if end < 0:
            return None
        fields = stat_line[end + 2 :].split()
        return int(fields[19])
    except (OSError, UnicodeError, ValueError, IndexError):
        return None


def _session_matches(generation: str) -> bool:
    try:
        # This is the same installed root used by all Stow launchers. Do not
        # resolve __file__: under Stow that points into the tui source package.
        sys.path.insert(0, str(Path.home() / ".local" / "lib"))
        import bwsession

        status = bwsession.status()
        return (
            isinstance(status, dict)
            and status.get("schema") == 1
            and status.get("state") == "unlocked"
            and status.get("generation") == generation
            and isinstance(status.get("deadline"), int)
            and not isinstance(status.get("deadline"), bool)
            and status["deadline"] > int(time.time())
        )
    except Exception:
        return False


def _pidfd_kill(pidfd: int) -> None:
    try:
        signal.pidfd_send_signal(pidfd, signal.SIGKILL)
    except OSError:
        pass


def _provider_preexec(parent_pid: int):
    def set_parent_death_signal() -> None:
        libc = ctypes.CDLL(None, use_errno=True)
        if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
            os._exit(127)
        if os.getppid() != parent_pid:
            os._exit(127)

    return set_parent_death_signal


def _read_secret(fd, length: int, deadline: float) -> bytearray:
    result = bytearray()
    while len(result) < length:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError
        readable, _, _ = select.select([fd.fileno()], [], [], remaining)
        if not readable:
            raise TimeoutError
        chunk = os.read(fd.fileno(), min(65_536, length - len(result)))
        if not chunk:
            raise EOFError
        result.extend(chunk)
    return result


def _stop_provider(provider: subprocess.Popen[bytes], pidfd: int) -> None:
    if provider.poll() is not None:
        return
    try:
        signal.pidfd_send_signal(pidfd, signal.SIGTERM)
        provider.wait(timeout=0.5)
        return
    except (OSError, subprocess.TimeoutExpired):
        pass
    _pidfd_kill(pidfd)
    try:
        provider.wait(timeout=0.5)
    except subprocess.TimeoutExpired:
        pass


def _write_provider(provider: subprocess.Popen[bytes], secret: bytearray) -> None:
    if provider.stdin is None:
        raise BrokenPipeError
    remaining = memoryview(secret)
    fd = provider.stdin.fileno()
    while remaining:
        written = os.write(fd, remaining)
        if written <= 0:
            raise BrokenPipeError
        remaining = remaining[written:]
    provider.stdin.close()


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 6:
        return 2

    try:
        wl_copy, generation, sensitive_arg, ttl_arg, length_arg, ready_fd_arg = args
        ttl = int(ttl_arg)
        length = int(length_arg)
        ready_fd = int(ready_fd_arg)
        if (
            not Path(wl_copy).is_absolute()
            or len(generation) != 8
            or any(c not in "0123456789abcdefABCDEF" for c in generation)
            or sensitive_arg not in {"0", "1"}
            or not 1 <= ttl <= 300
            or not 0 <= length <= _MAX_BYTES
            or ready_fd < 0
        ):
            return 2
    except (TypeError, ValueError):
        return 2

    if not _session_matches(generation):
        try:
            os.write(ready_fd, b"0")
        except OSError:
            pass
        finally:
            os.close(ready_fd)
        return 2

    command = [wl_copy, "--foreground", "--type", "text/plain;charset=utf-8"]
    if sensitive_arg == "1":
        command.append("--sensitive")
    child_env = os.environ.copy()
    child_env.pop("BW_SESSION", None)
    child_env["BW_NOINTERACTION"] = "true"
    for name in tuple(child_env):
        if name.startswith(("PYTHON", "TEXTUAL_")):
            child_env.pop(name, None)
    runtime_dir = child_env.get("XDG_RUNTIME_DIR")
    if runtime_dir and Path(runtime_dir).is_dir():
        child_env["TMPDIR"] = runtime_dir

    parent_pid = os.getpid()
    provider: subprocess.Popen[bytes] | None = None
    pidfd = -1
    deadline_timer: threading.Timer | None = None
    ttl_deadline = 0.0
    try:
        provider = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=child_env,
            close_fds=True,
            start_new_session=True,
            preexec_fn=_provider_preexec(parent_pid),
        )
        if provider.stdin is None:
            return 2
        pidfd = os.pidfd_open(provider.pid, 0)
        ttl_deadline = time.monotonic() + ttl

        # A separate timer enforces the TTL even while a status() call is
        # blocked in its bounded Bitwarden CLI wait.
        deadline_timer = threading.Timer(
            max(0.0, ttl_deadline - time.monotonic()),
            _pidfd_kill,
            args=(pidfd,),
        )
        deadline_timer.daemon = True
        deadline_timer.start()

        try:
            os.write(ready_fd, b"1")
        except OSError:
            _stop_provider(provider, pidfd)
            return 2
        finally:
            os.close(ready_fd)

        try:
            secret = _read_secret(sys.stdin.buffer, length, ttl_deadline)
        except (EOFError, OSError, TimeoutError, ValueError):
            _stop_provider(provider, pidfd)
            return 2

        try:
            _write_provider(provider, secret)
        except (BrokenPipeError, OSError, ValueError):
            _stop_provider(provider, pidfd)
            return 2
        finally:
            secret[:] = b"\0" * len(secret)
            del secret

        while time.monotonic() < ttl_deadline:
            if provider.poll() is not None:
                return 0
            if not _session_matches(generation):
                break
            if provider.poll() is not None:
                return 0
            time.sleep(min(STATUS_POLL_INTERVAL, max(0.05, ttl_deadline - time.monotonic())))
        _stop_provider(provider, pidfd)
        return 0
    except (OSError, subprocess.SubprocessError, ValueError):
        if provider is not None and pidfd >= 0:
            _stop_provider(provider, pidfd)
        return 2
    finally:
        if deadline_timer is not None:
            deadline_timer.cancel()
            deadline_timer.join(timeout=1.0)
        try:
            os.close(ready_fd)
        except OSError:
            pass
        if pidfd >= 0:
            if provider is not None and provider.poll() is None:
                _stop_provider(provider, pidfd)
            os.close(pidfd)


if __name__ == "__main__":
    raise SystemExit(main())

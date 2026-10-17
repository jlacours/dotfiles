"""A small runtime lock that prevents overlapping unlock cards."""

from __future__ import annotations

import fcntl
import os
import stat


class InstanceAlreadyRunning(RuntimeError):
    """Another unlock card already holds the session-local lock."""


def acquire_unlock_card_lock() -> int:
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime or not os.path.isabs(runtime):
        raise OSError
    runtime_stat = os.stat(runtime, follow_symlinks=False)
    if (
        not stat.S_ISDIR(runtime_stat.st_mode)
        or runtime_stat.st_uid != os.getuid()
        or runtime_stat.st_mode & 0o077
    ):
        raise OSError
    path = os.path.join(runtime, "jujutui-unlock-card.lock")
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    lock_stat = os.fstat(fd)
    if (
        not stat.S_ISREG(lock_stat.st_mode)
        or lock_stat.st_uid != os.getuid()
        or lock_stat.st_mode & 0o077
    ):
        os.close(fd)
        raise OSError
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        os.close(fd)
        raise InstanceAlreadyRunning from exc
    return fd

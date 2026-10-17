"""Small adapter around the bwsession contract; errors are never echoed."""

from __future__ import annotations

import importlib
import re
import threading
import time
from contextlib import contextmanager
from collections.abc import Mapping
from collections.abc import Iterator

_GENERATION = re.compile(r"[0-9a-fA-F]{8}\Z")
_TICKET = re.compile(r"(?:[0-9a-fA-F]{16})?\Z")
_ITEM_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
_VALID_STATES = {
    "unlocked",
    "locked",
    "unauthenticated",
    "keyring-locked",
    "error",
}
_MAX_SECRET_BYTES = 1_048_576
BACKEND_LOCK_WAIT_SECONDS = 25.0
_BACKEND_LOCK_POLL_SECONDS = 0.05
_BACKEND_LOCK = threading.RLock()


class SessionError(RuntimeError):
    """Fixed, sanitized session or backend failure."""


class SessionLocked(SessionError):
    """The vault is no longer unlocked."""


class SessionExpired(SessionError):
    """The session generation changed or reached its deadline."""


class SessionBusy(SessionError):
    """The serialized backend connection did not become available in time."""


class SessionCancelled(SessionError):
    """A caller was canceled while waiting to enter the backend."""


class SessionWrongPassword(SessionError):
    """The backend rejected the submitted master password."""


def _backend():
    try:
        return importlib.import_module("bwsession")
    except Exception as exc:
        raise SessionError from exc


@contextmanager
def _backend_call(
    cancel_event: threading.Event | None = None,
) -> Iterator[None]:
    deadline = time.monotonic() + BACKEND_LOCK_WAIT_SECONDS
    while True:
        if cancel_event is not None and cancel_event.is_set():
            raise SessionCancelled
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise SessionBusy
        if _BACKEND_LOCK.acquire(
            timeout=min(_BACKEND_LOCK_POLL_SECONDS, remaining)
        ):
            break
    try:
        if cancel_event is not None and cancel_event.is_set():
            raise SessionCancelled
        yield
    finally:
        _BACKEND_LOCK.release()


def status_snapshot(
    *, cancel_event: threading.Event | None = None
) -> dict[str, object]:
    """Read and validate the fixed-schema status without opening a keyring prompt."""
    try:
        with _backend_call(cancel_event):
            raw = _backend().status()
    except SessionError:
        raise
    except Exception as exc:
        raise SessionError from exc

    schema = raw.get("schema") if isinstance(raw, Mapping) else None
    if not isinstance(raw, Mapping) or not isinstance(schema, int) or isinstance(schema, bool) or schema != 1:
        raise SessionError
    state = raw.get("state")
    deadline = raw.get("deadline")
    generation = raw.get("generation")
    if state not in _VALID_STATES:
        raise SessionError
    if deadline is not None and (not isinstance(deadline, int) or isinstance(deadline, bool)):
        raise SessionError
    if generation is not None and (
        not isinstance(generation, str) or not _GENERATION.fullmatch(generation)
    ):
        raise SessionError
    if state == "unlocked":
        if deadline is None or generation is None:
            raise SessionError
        if deadline <= int(time.time()):
            raise SessionExpired
    return {
        "schema": 1,
        "state": state,
        "deadline": deadline,
        "generation": generation,
    }


def require_unlocked(
    expected_generation: str | None = None,
    *,
    cancel_event: threading.Event | None = None,
) -> dict[str, object]:
    snapshot = status_snapshot(cancel_event=cancel_event)
    if snapshot["state"] != "unlocked":
        raise SessionLocked
    generation = snapshot["generation"]
    if expected_generation is not None and generation != expected_generation:
        raise SessionExpired
    return snapshot


def validate_generation(generation: object) -> str:
    """Validate a generation token received from a bound picker handoff."""
    if not isinstance(generation, str) or not _GENERATION.fullmatch(generation):
        raise SessionError
    return generation


def validate_item_id(item_id: object) -> str:
    if not isinstance(item_id, str) or not _ITEM_ID.fullmatch(item_id):
        raise SessionError
    return item_id


def item_meta(item_id: str) -> dict[str, object]:
    item_id = validate_item_id(item_id)
    snapshot = require_unlocked()
    try:
        with _backend_call():
            raw = _backend().meta(item_id)
    except Exception as exc:
        raise SessionError from exc
    if not isinstance(raw, Mapping):
        raise SessionError

    # Recheck after the metadata request so a response from an old generation
    # never remains on screen after a concurrent lock or re-unlock.
    require_unlocked(str(snapshot["generation"]))
    name = raw.get("name")
    username = raw.get("username")
    uris = raw.get("uris")
    if not isinstance(name, str):
        raise SessionError
    if username is not None and not isinstance(username, str):
        raise SessionError
    if not isinstance(uris, list) or any(not isinstance(uri, str) for uri in uris):
        raise SessionError
    return {
        "name": name,
        "username": username,
        "uris": uris[:10],
    }


def item_secret(
    item_id: str,
    field: str,
    generation: str,
    *,
    cancel_event: threading.Event | None = None,
) -> bytes:
    item_id = validate_item_id(item_id)
    if field not in {"password", "username"}:
        raise SessionError
    if not isinstance(generation, str) or not _GENERATION.fullmatch(generation):
        raise SessionExpired
    require_unlocked(generation, cancel_event=cancel_event)
    backend = _backend()
    try:
        with _backend_call(cancel_event):
            value = backend.secret(item_id, field, generation)
    except (SessionBusy, SessionCancelled):
        raise
    except Exception as exc:
        if type(exc).__name__ == "Expired":
            raise SessionExpired from exc
        raise SessionError from exc
    if not isinstance(value, bytes) or len(value) > _MAX_SECRET_BYTES:
        raise SessionError

    # Do not return material if lock/expiry raced with the backend call.
    try:
        require_unlocked(generation, cancel_event=cancel_event)
    except SessionError:
        del value
        raise SessionExpired
    return value


def cancel_unlocks() -> None:
    """Invalidate an unlock without the Secret Service lock so it can interrupt it."""
    try:
        _backend().cancel_unlocks()
    except Exception as exc:
        raise SessionError from exc


def unlock_ticket() -> str:
    """Capture W's cancellation epoch before scheduling an unlock worker."""
    try:
        with _backend_call():
            ticket = _backend().unlock_ticket()
    except Exception as exc:
        raise SessionError from exc
    if not isinstance(ticket, str) or not _TICKET.fullmatch(ticket):
        raise SessionError
    return ticket


def unlock_session(
    password: bytes,
    ticket: str,
    *,
    cancel_event: threading.Event | None = None,
) -> str:
    """Perform a ticket-bound desktop unlock under T's backend-call lock."""
    if not isinstance(ticket, str) or not _TICKET.fullmatch(ticket):
        raise SessionError
    with _backend_call(cancel_event):
        if cancel_event is not None and cancel_event.is_set():
            raise SessionCancelled
        try:
            generation = _backend().unlock(password, desktop=True, ticket=ticket)
        except Exception as exc:
            if type(exc).__name__ == "WrongPassword":
                raise SessionWrongPassword from exc
            if type(exc).__name__ == "Error" and cancel_event is not None and cancel_event.is_set():
                raise SessionCancelled from exc
            raise SessionError from exc
    if not isinstance(generation, str) or not _GENERATION.fullmatch(generation):
        raise SessionError
    return generation


def lock_generation(generation: str) -> None:
    """Revoke one specific late unlock success without locking a newer session."""
    if not isinstance(generation, str) or not _GENERATION.fullmatch(generation):
        raise SessionError
    try:
        with _backend_call():
            _backend().lock_generation(generation)
    except Exception as exc:
        raise SessionError from exc


def desktop_unlocked() -> bool:
    """Read the shared graphical-session gate; errors fail closed."""
    try:
        return _backend().desktop_unlocked() is True
    except Exception:
        return False

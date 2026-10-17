"""bwsession: the single authority for the Bitwarden CLI session.

Public contract (see ~/.dotfiles/bitwarden/README.md):

    status()                      -> {"schema":1,"state":..., "deadline":int|None,
                                      "generation":str|None, "message":str}
    unlock_ticket()               -> str: take when an unlock attempt starts (before
                                     scheduling a worker or waiting)
    unlock(password: bytes, desktop=True, ticket=None) -> committed generation (str),
                                     raises WrongPassword / Error; aborts if
                                     cancel_unlocks() or a lock happened after `ticket`
                                     (desktop: refused/cancelled while the desktop is locked)
    cancel_unlocks()              -> None: abort every attempt that has not committed
    lock(reason="manual")         -> None, raises Error when cleanup is incomplete
    lock_generation(generation)   -> None: revoke that session if it is still current
                                     (an attempt that succeeded after it was abandoned)
    meta(item_id)                 -> {"name": str, "username": str|None, "uris": [str]}
    secret(item_id, field, generation) -> bytes, raises Expired
    pick() / pick_bound()         -> item ID / (item ID, generation) or None
    desktop_unlocked()            -> bool: active, unlocked graphical session

Importing this module disables core dumps for the current process tree.
Only the default Bitwarden CLI profile is managed; a caller environment that
selects another one (BITWARDENCLI_APPDATA_DIR, XDG_CONFIG_HOME) is refused.
Same-user code is not isolated from an unlocked vault; this layer only keeps
secrets out of argv, logs and disk and bounds the session lifetime.

All functions may be called from several threads at once (see _core and
_keyring for the thread-safety contract).
"""

import threading

from ._core import Authority, Error, Expired, WrongPassword, sanitize
from ._harden import harden_process

harden_process()

__all__ = [
    "Error", "Expired", "WrongPassword",
    "status", "unlock", "unlock_ticket", "lock", "lock_generation", "meta", "secret",
    "pick", "pick_bound", "remind", "desktop_unlocked", "cancel_unlocks", "sanitize",
]

PUBLIC_LOCK_REASONS = ("manual", "expired", "suspend", "screenlock", "idle")

_authority = None
_authority_lock = threading.Lock()


def _default(internal=False):
    """The process-wide Authority.  `internal` (guard, timer callback) manages
    the canonical profile whatever the caller's profile variables say."""
    global _authority
    with _authority_lock:
        if _authority is None:
            _authority = Authority(enforce_profile=not internal)
        return _authority


def status():
    return _default().status()


def unlock_ticket():
    try:
        return _default().cancel_token()
    except Exception:
        raise Error("Unlock unavailable") from None


def unlock(password, desktop=True, ticket=None):
    try:
        return _default().unlock(password, desktop=desktop, ticket=ticket)
    except Error:
        raise
    except Exception:
        raise Error("Unlock failed") from None


def lock(reason="manual"):
    if reason not in PUBLIC_LOCK_REASONS:
        raise Error("Unknown lock reason")
    try:
        complete = _default().revoke(reason)
    except Exception:
        raise Error("Lock failed") from None
    if not complete:
        raise Error("Lock incomplete; cleanup pending")


def lock_generation(generation, reason="manual"):
    if reason not in PUBLIC_LOCK_REASONS:
        raise Error("Unknown lock reason")
    try:
        complete = _default().lock_generation(generation, reason)
    except Error:
        raise
    except Exception:
        raise Error("Lock failed") from None
    if not complete:
        raise Error("Lock incomplete; cleanup pending")


def meta(item_id):
    try:
        return _default().meta(item_id)
    except Error:
        raise
    except Exception:
        raise Error("Item lookup failed") from None


def secret(item_id, field, generation):
    try:
        return _default().secret(item_id, field, generation)
    except Error:
        raise
    except Exception:
        raise Error("Secret lookup failed") from None


def pick_bound():
    """(item ID, generation) chosen while that generation stayed current, or None."""
    from ._desktop import pick as _pick

    try:
        return _pick(_default())
    except Error:
        raise
    except Exception:
        raise Error("Picker failed") from None


def pick():
    chosen = pick_bound()
    return chosen[0] if chosen else None


def desktop_unlocked():
    from ._desktop import desktop_unlocked as _desktop_unlocked

    try:
        return _desktop_unlocked()
    except Exception:
        return False


def cancel_unlocks():
    """Invalidate any unlock transition that has not committed yet."""
    try:
        _default().cancel_unlocks()
    except Exception:
        raise Error("Unable to cancel pending unlock") from None


def remind():
    from ._desktop import remind as _remind

    try:
        return _remind(_default())
    except Exception:
        return "error"

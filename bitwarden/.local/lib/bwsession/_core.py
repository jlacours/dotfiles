"""Session authority: one keyring record, serialized transitions, fail closed.

Runtime state ($XDG_RUNTIME_DIR/bwsession, 0700; files 0600, no secrets):

    cancel    cancellation token, replaced (random) by every revocation and by
              cancel_unlocks().  An unlock captures it as its ticket before it
              waits for anything and commits only if it is unchanged.
    epoch     lock period, replaced by every revocation and cleanup; owned
              children, pickers and status/session reads stop or re-check
              when it changes
    pending   tombstone: written *before* a revocation tries to take the
              transition lock, removed only by a complete cleanup.  While it
              exists every reader denies access.
    txn       written under the transition lock before `bw unlock` runs and
              removed at commit.  Found while the lock is free, it marks an
              interrupted unlock, which is revoked.
    verified  short status cache (never extends a session)
    remind    reminder rate limit

Every transition holds flock($XDG_RUNTIME_DIR/bwsession.lock).  A caller
that cannot get it never touches records or runtime state, except for the
tombstone/cancel/epoch writes above, which are single atomic renames.

Commit/cancel order: cancel_unlocks() and the tombstone write take a second,
short lock (bwsession.cancel.lock) that an unlock also holds for its final
check and the removal of `txn` (the commit point).  A cancellation is thus
either seen by that check, or happened after commit; readers only accept a
record while neither `txn` nor `pending` exists.  A cancel after commit does
not end the session (LOCK_ON_SCREENLOCK=no keeps sessions across screen
lock); a caller that abandoned its attempt revokes the generation unlock()
returned (bwsession.lock_generation).

Thread safety: an Authority may be shared by threads.  Transitions use
flock on a fresh descriptor per call (exclusive between threads too),
runtime files are replaced atomically, the keyring backend serializes its
own operations with a bounded wait (see _keyring), and deadlines are
per thread.

Budgets: _within(seconds) sets a per-thread deadline that caps every
blocking step underneath it (lock waits, `bw` children, keyring calls, timer
calls).  Work that runs out of time is left to the tombstone, so access
stays denied.  A child killed at the deadline may take up to 0.5 s more to
be reaped.
"""

import contextlib
import errno
import fcntl
import getpass
import hashlib
import json
import os
import pwd
import re
import secrets
import stat
import threading
import time
import unicodedata

from . import _bw
from ._config import load_config
from ._keyring import KeyringError, KeyringLocked, KeyringUnavailable, SecretServiceKeyring
from ._timer import SystemdTimers

SCHEMA = 1
RECORD_VERSION = 2
APPLICATION = "bwsession"
LEGACY_APPLICATION = "bitwarden-cli-session"
LABEL = "Bitwarden CLI session (bw-session)"
LOCK_REASONS = ("manual", "expired", "suspend", "screenlock", "idle", "migrate", "replace", "invalid")
MAX_PASSWORD_BYTES = 4096
CLOCK_SKEW = 120  # tolerated backwards wall-clock step, seconds
# BOOTTIME - MONOTONIC grows only while suspended; the tolerance absorbs the
# few microseconds between the two clock reads, so any real suspend counts.
SLEEP_TOLERANCE = 0.05
VERIFY_UNLOCKED_SECONDS = 120
VERIFY_LOCKED_SECONDS = 300
READER_LOCK_SECONDS = 2
STATUS_BUDGET = 8.0  # whole status() call, below Q's 10 s relay timeout
CANCEL_LOCK_SECONDS = 5

_GENERATION = re.compile(r"^[0-9a-f]{8}$")
_TOKEN = re.compile(r"^[A-Za-z0-9+/=_-]{16,512}$")
_ITEM_ID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

MESSAGES = {
    "unlocked": "Vault unlocked",
    "locked": "Vault locked",
    "unauthenticated": "Not logged in to Bitwarden",
    "keyring-locked": "Login keyring is locked",
    "error": "Bitwarden session error",
}
EXPIRED = "Vault locked or session expired"
PROFILE_REFUSED = "Only the default Bitwarden CLI profile is managed"


class Error(Exception):
    """Fixed, sanitized failure message; never carries secret data."""


class WrongPassword(Error):
    pass


class Expired(Error):
    pass


def sanitize(text, limit=120):
    """Literal single-line text: control, format (bidi) and separator chars removed."""
    if not isinstance(text, str):
        return ""
    out = []
    for char in text:
        category = unicodedata.category(char)
        if char in "\t\r\n" or category in ("Zl", "Zp"):
            out.append(" ")
        elif category in ("Cc", "Cf", "Cs", "Co", "Cn"):
            continue
        else:
            out.append(char)
    return " ".join("".join(out).split())[:limit]


def valid_item_id(item_id):
    return isinstance(item_id, str) and bool(_ITEM_ID.match(item_id))


def valid_generation(generation):
    return isinstance(generation, str) and bool(_GENERATION.match(generation))


class Clock:
    def wall(self):
        return time.time()

    def boottime(self):
        return time.clock_gettime(time.CLOCK_BOOTTIME)

    def slept(self):
        """Total time this boot spent suspended (BOOTTIME - MONOTONIC)."""
        return time.clock_gettime(time.CLOCK_BOOTTIME) - time.clock_gettime(time.CLOCK_MONOTONIC)

    def boot_id(self):
        try:
            with open("/proc/sys/kernel/random/boot_id", encoding="ascii") as handle:
                return handle.read(64).strip()
        except OSError:
            return ""


def _runtime_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    path = os.path.join(base, "bwsession")
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    info = os.lstat(path)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise Error("unsafe runtime directory")
    if stat.S_IMODE(info.st_mode) != 0o700:
        os.chmod(path, 0o700)
    return path


def _passwd_home():
    try:
        return pwd.getpwuid(os.getuid()).pw_dir
    except KeyError:
        return ""


def _default_desktop_gate(full):
    from . import _desktop

    return _desktop.desktop_unlocked() if full else not _desktop.hyprlock_running()


class Authority:
    def __init__(self, keyring=None, timers=None, bw=None, config=None, clock=None,
                 runtime_dir=None, environ=None, migrate_legacy=None, enforce_profile=True,
                 desktop_gate=None):
        self._keyring = keyring
        self.timers = timers or SystemdTimers()
        self.bw = bw  # path override for tests; None = /usr/bin/bw
        self._config = config
        self.clock = clock or Clock()
        self._runtime = runtime_dir
        self.desktop_gate = desktop_gate or _default_desktop_gate
        self._local = threading.local()
        self._keyring_lock = threading.Lock()
        environ = os.environ if environ is None else environ
        self.account = environ.get("USER") or getpass.getuser()
        self.home = environ.get("HOME") or os.path.expanduser("~")
        canonical = _bw.canonical_profile(self.home)
        # Only the canonical profile is managed (children never get profile
        # variables).  A caller that asks for another one is refused, not
        # silently redirected; internal entry points ignore caller variables.
        self.profile_refused = enforce_profile and _bw.profile_dir(environ) != canonical
        self.profile = hashlib.sha256(canonical.encode()).hexdigest()[:16]
        # The pre-bwsession wrapper's item is unscoped: only migrate it for the real home.
        if migrate_legacy is None:
            migrate_legacy = self.home == _passwd_home()
        self.migrate_legacy = migrate_legacy

    # -- infrastructure ----------------------------------------------------
    @property
    def keyring(self):
        with self._keyring_lock:
            if self._keyring is None:
                self._keyring = SecretServiceKeyring()
            return self._keyring

    @contextlib.contextmanager
    def _within(self, seconds):
        """Per-thread deadline for everything below (see the module docstring)."""
        deadline = time.monotonic() + seconds
        previous = getattr(self._local, "deadline", None)
        if previous is not None and previous < deadline:
            deadline = previous
        self._local.deadline = deadline
        try:
            with self.keyring.bounded(deadline):
                yield deadline
        finally:
            self._local.deadline = previous

    def _left(self, cap):
        """Seconds available for a blocking step (<= 0 when out of time)."""
        deadline = getattr(self._local, "deadline", None)
        if deadline is None:
            return cap
        return min(cap, deadline - time.monotonic())

    def _bw_lock(self, cap=20):
        timeout = self._left(cap)
        if timeout < 0.1:
            return None
        return _bw.lock(bw=self.bw, home=self.home, timeout=timeout)

    def _bw_status(self, session):
        timeout = self._left(20)
        if timeout < 0.1:
            raise _bw.BwFailure("out of time")
        return _bw.status(session=session, bw=self.bw, home=self.home, timeout=timeout)

    @property
    def config(self):
        return self._config or load_config()

    @property
    def runtime(self):
        if self._runtime is None:
            self._runtime = _runtime_dir()
        return self._runtime

    def _path(self, name):
        return os.path.join(self.runtime, name)

    def _check_profile(self):
        if self.profile_refused:
            raise Error(PROFILE_REFUSED)

    @contextlib.contextmanager
    def _flocked(self, name, timeout):
        lock_path = os.path.join(os.path.dirname(self.runtime), name)
        fd = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
        acquired = False
        try:
            deadline = time.monotonic() + max(self._left(timeout), 0)
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    acquired = True
                    break
                except OSError as exc:
                    if exc.errno not in (errno.EAGAIN, errno.EACCES) or time.monotonic() >= deadline:
                        break
                    time.sleep(0.02)
            yield acquired
        finally:
            os.close(fd)

    def serialized(self, timeout):
        """flock on $XDG_RUNTIME_DIR/bwsession.lock; yields whether it was acquired."""
        return self._flocked("bwsession.lock", timeout)

    def _commit_order(self):
        """Short lock ordering cancellations against an unlock's commit point."""
        return self._flocked("bwsession.cancel.lock", CANCEL_LOCK_SECONDS)

    def _read_json(self, name):
        try:
            with open(self._path(name), encoding="utf-8") as handle:
                value = json.loads(handle.read(4096))
            return value if isinstance(value, dict) else None
        except (OSError, ValueError):
            return None

    def _exists(self, name):
        return os.path.lexists(self._path(name))

    def _write_json(self, name, value):
        path = self._path(name)
        tmp = f"{path}.{os.getpid()}.{secrets.token_hex(4)}.tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)

    def _remove(self, name):
        with contextlib.suppress(FileNotFoundError):
            os.unlink(self._path(name))

    # -- cancellation, epoch and tombstone ----------------------------------
    def epoch(self):
        value = (self._read_json("epoch") or {}).get("e")
        return value if isinstance(value, str) else ""

    def _new_epoch(self):
        self._write_json("epoch", {"e": secrets.token_hex(8)})

    def cancel_token(self):
        """Ticket for an unlock attempt; take it before scheduling or waiting."""
        value = (self._read_json("cancel") or {}).get("c")
        return value if isinstance(value, str) else ""

    def cancel_unlocks(self):
        """Every unlock that has not committed yet aborts (committed sessions stay)."""
        with self._commit_order():
            # Without the lock (a holder stuck for 5 s) the write still happens:
            # holders only do short file operations, never wait on this.
            self._write_json("cancel", {"c": secrets.token_hex(8)})

    def _tombstone(self, reason):
        """Deny every reader and cancel every pending unlock, before any lock wait."""
        reason = reason if reason in LOCK_REASONS else "invalid"
        with self._commit_order():
            self._write_json("pending", {"reason": reason, "bw_locked": False})
            self._write_json("cancel", {"c": secrets.token_hex(8)})
            self._new_epoch()

    def revoked_since(self, epoch):
        """Cheap check for owned children and pickers (two stat-sized reads)."""
        return self.epoch() != epoch or self._exists("pending")

    # -- keyring record ----------------------------------------------------
    def _attributes(self):
        return {"application": APPLICATION, "account": self.account,
                "profile": self.profile, "schema": str(SCHEMA)}

    def _search(self):
        records = self.keyring.search(self._attributes())
        legacy = []
        if self.migrate_legacy:
            legacy = self.keyring.search({"application": LEGACY_APPLICATION, "account": self.account})
        return records, legacy

    def _load(self, item):
        """Parsed record dict, or None when missing/invalid/legacy."""
        raw = self.keyring.get_secret(item)
        try:
            record = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            return None
        if not isinstance(record, dict) or record.get("v") != RECORD_VERSION:
            return None
        checks = (
            isinstance(record.get("token"), str) and _TOKEN.match(record["token"]),
            valid_generation(record.get("generation")),
            isinstance(record.get("issued_at"), int),
            isinstance(record.get("deadline"), int),
            isinstance(record.get("ttl"), int) and record["ttl"] > 0,
            isinstance(record.get("boot_id"), str) and record["boot_id"],
            isinstance(record.get("boottime"), (int, float)),
            isinstance(record.get("slept"), (int, float)),
        )
        return record if all(checks) else None

    def effective_deadline(self, record):
        """Wall-clock deadline, or None when the record is no longer valid."""
        config = self.config
        ttl = min(record["ttl"], config.ttl_seconds)
        now = self.clock.wall()
        elapsed = self.clock.boottime() - record["boottime"]
        deadline = min(record["deadline"], record["issued_at"] + ttl)
        if record["boot_id"] != self.clock.boot_id():
            return None
        if not record["issued_at"] - CLOCK_SKEW <= now < deadline:
            return None
        if not 0 <= elapsed < ttl:
            return None
        # Any suspend since unlock ends the session, whether or not the guard saw it.
        if config.lock_on_suspend and self.clock.slept() - record["slept"] > SLEEP_TOLERANCE:
            return None
        return int(min(deadline, now + (ttl - elapsed)))

    def _item_generation(self, item):
        generation = self.keyring.item_generation(item)
        return generation if valid_generation(generation) else None

    # -- revocation --------------------------------------------------------
    def _cleanup(self, reason):
        """Under the transition lock: lock the CLI profile, remove every record.

        Returns True when complete.  Never prompts.  Real `bw lock` runs
        first, whether or not the keyring is reachable; anything left over
        keeps the tombstone (no secrets) so that readers deny and retry.
        Every blocking step honours the caller's _within() deadline.
        """
        reason = reason if reason in LOCK_REASONS else "invalid"
        self._new_epoch()  # owned children and pickers stop now
        state = self._bw_lock()
        complete = state is not None
        generations = []
        try:
            records, legacy = self._search()
            for item in records + legacy:
                with contextlib.suppress(KeyringError):
                    generations.append(self._item_generation(item))
                try:
                    self.keyring.delete(item)
                except KeyringError:
                    complete = False
        except KeyringError:
            complete = False
        # A leftover timer is harmless (its callback no-ops for a non-current generation).
        for generation in generations:
            timeout = self._left(10)
            if generation and timeout >= 0.1:
                self.timers.disarm(generation, timeout=timeout)
        self._remove("verified")
        if not complete:
            self._write_json("pending", {"reason": reason, "bw_locked": state is not None})
            self._remove("txn")
            return False
        self._remove("txn")
        self._remove("pending")
        self._remember(f"none:{self.epoch()}", state)
        return True

    def revoke(self, reason, timeout=15, budget=None):
        """Tombstone first, then clean up under the lock.  True only when complete.

        Without the lock (a stuck or slow holder), records are left to the
        holder or the next reader; only the idempotent profile `bw lock` runs,
        and the in-flight transition aborts on the new cancel token.
        `budget` (seconds) caps every blocking step of the call, e.g. a sleep
        inhibitor's delay; what does not fit stays pending (access denied).
        """
        self._check_profile()
        self._tombstone(reason)
        with contextlib.ExitStack() as stack:
            if budget is not None:
                stack.enter_context(self._within(budget))
                timeout = min(timeout, budget / 3)
            with self.serialized(timeout) as acquired:
                if acquired:
                    return self._cleanup(reason)
            self._bw_lock()
            return False

    def revoke_generation(self, generation, reason, timeout=READER_LOCK_SECONDS):
        """Revoke only if `generation` (or an unidentifiable record) is still current.

        Needs the lock: a reader that saw an old generation must not tear down
        a session that a concurrent unlock committed in the meantime.  Without
        it nothing is changed (the reader denies anyway).  Returns True when
        `generation` is no longer usable and nothing is left to clean.
        """
        with self.serialized(timeout) as acquired:
            if not acquired:
                return False
            try:
                records, legacy = self._search()
                current = {self._item_generation(item) for item in records}
            except KeyringError:
                current, legacy = {None}, []
            if not legacy and generation not in current and None not in current:
                return True
            return self._cleanup(reason)

    def lock_generation(self, generation, reason="manual"):
        """Revoke one attempt's session (e.g. its unlock succeeded after it was abandoned)."""
        self._check_profile()
        if not valid_generation(generation):
            raise Error("Invalid generation")
        return self.revoke_generation(generation, reason, timeout=15)

    def _recover(self, timeout=READER_LOCK_SECONDS):
        """Finish a pending revocation or an interrupted unlock.  True when clean.

        A txn marker found while the lock is free belongs to a dead unlock.
        """
        if not (self._exists("pending") or self._exists("txn")):
            return True
        with self.serialized(timeout) as acquired:
            if not acquired:
                return False
            pending = self._read_json("pending")
            if pending is None and not self._exists("txn"):
                return True
            return self._cleanup((pending or {}).get("reason", "invalid"))

    # -- status ------------------------------------------------------------
    def _result(self, state, deadline=None, generation=None):
        return {"schema": 1, "state": state, "deadline": deadline,
                "generation": generation, "message": MESSAGES[state]}

    def _cached(self, key, max_age):
        cached = self._read_json("verified")
        if not cached or cached.get("key") != key:
            return None
        at = cached.get("at")
        if not isinstance(at, (int, float)):
            return None
        if not 0 <= self.clock.boottime() - at < max_age:
            return None
        return cached.get("state")

    def _remember(self, key, state):
        self._write_json("verified", {"key": key, "state": state, "at": self.clock.boottime()})

    def status(self):
        """Never prompts.  The whole call is bounded by STATUS_BUDGET."""
        if self.profile_refused:
            return self._result("error")
        try:
            with self._within(STATUS_BUDGET):
                return self._result(*self._status())
        except KeyringUnavailable:
            return self._result("error")
        except KeyringLocked:
            return self._result("keyring-locked")
        except (KeyringError, _bw.BwFailure, Error, OSError):
            return self._result("error")

    def _status(self, depth=0):
        if not self._recover():
            if self._exists("txn") and not self._exists("pending"):
                return ("locked",)  # an unlock is in flight; nothing is committed yet
            pending = self._read_json("pending") or {}
            if pending.get("bw_locked") and self.keyring.collection_locked():
                return ("keyring-locked",)
            return ("error",)
        epoch = self.epoch()  # any revocation from here on invalidates this read
        if self.keyring.collection_locked():
            return ("keyring-locked",)
        records, legacy = self._search()
        if legacy or len(records) > 1:
            if not self.revoke("migrate" if legacy else "invalid"):
                return ("error",)
            return self._unmanaged_state()
        if any(item.locked for item in records):
            return ("keyring-locked",)
        if not records:
            return self._unmanaged_state()
        item_generation = self._item_generation(records[0])
        record = self._load(records[0])
        deadline = self.effective_deadline(record) if record else None
        if deadline is None:
            return self._after_revoke(item_generation, "expired" if record else "invalid", depth)
        key = f"gen:{record['generation']}"
        if self._cached(key, VERIFY_UNLOCKED_SECONDS) != "unlocked":
            state = self._bw_status(record["token"])
            if state != "unlocked":
                return self._after_revoke(record["generation"], "invalid", depth)
            self._remember(key, "unlocked")
        # Only report what is still true: same lock period, nothing pending, the
        # same single record, deadline re-evaluated now.
        if not self._still_current(epoch, record):
            return self._status(depth + 1) if depth == 0 else ("locked",)
        deadline = self.effective_deadline(record)
        if deadline is None:
            return self._after_revoke(record["generation"], "expired", depth)
        return ("unlocked", deadline, record["generation"])

    def _still_current(self, epoch, record):
        if self.revoked_since(epoch) or self._exists("txn"):
            return False
        records, legacy = self._search()
        if legacy or len(records) != 1 or records[0].locked:
            return False
        if self._item_generation(records[0]) != record["generation"]:
            return False
        return not (self.revoked_since(epoch) or self._exists("txn"))

    def _after_revoke(self, generation, reason, depth):
        if not self.revoke_generation(generation, reason):
            return ("error",)
        return self._status(depth + 1) if depth == 0 else ("locked",)

    def _unmanaged_state(self):
        """No record: the profile must be verified locked (`bw lock`) once per epoch."""
        key = f"none:{self.epoch()}"
        state = self._cached(key, VERIFY_LOCKED_SECONDS)
        if state in ("locked", "unauthenticated"):
            return (state,)
        with self.serialized(READER_LOCK_SECONDS) as acquired:
            if not acquired:
                return ("locked",) if self._exists("txn") else ("error",)
            records, legacy = self._search()
            if records or legacy or self._exists("pending") or self._exists("txn"):
                return ("error",)
            state = self._bw_lock()
            if state is None:
                return ("error",)
            self._remember(f"none:{self.epoch()}", state)
            return (state,)

    # -- unlock ------------------------------------------------------------
    def unlock(self, password, desktop=False, ticket=None):
        """Unlock with the master password; returns the committed generation.

        `ticket` is cancel_token() taken when the attempt was started (before
        it was scheduled or waited); by default it is taken on entry, before
        any wait.  Any cancel_unlocks() or revocation after the ticket aborts
        the attempt, up to its commit point.  `desktop` (a graphical prompt):
        refused while the desktop is locked, never commits behind a lock.
        """
        self._check_profile()
        if ticket is None:
            ticket = self.cancel_token()
        if isinstance(password, bytearray):
            password = bytes(password)
        if not isinstance(password, bytes) or not password:
            raise WrongPassword("Password is empty")
        if len(password) > MAX_PASSWORD_BYTES or any(b in password for b in b"\r\n\0"):
            raise Error("Password contains unsupported characters")
        try:
            password.decode("utf-8")
        except UnicodeDecodeError:
            raise Error("Password is not valid UTF-8") from None
        if not isinstance(ticket, str) or self.cancel_token() != ticket:
            raise Error("Unlock cancelled")
        if desktop and not self.desktop_gate(True):
            raise Error("Desktop is locked")
        with self.serialized(30) as acquired:
            if not acquired:
                raise Error("Another unlock or lock is in progress")
            if self.cancel_token() != ticket:
                raise Error("Unlock cancelled")
            try:
                return self._unlock_locked(password, desktop, ticket)
            except (KeyringUnavailable, OSError):
                raise Error("Secret Service is unavailable") from None
            except KeyringLocked:
                raise Error("Login keyring is locked") from None
            except KeyringError:
                raise Error("Secret Service error") from None

    def _cancelled(self, ticket, desktop):
        return self.cancel_token() != ticket or (desktop and not self.desktop_gate(False))

    def _check_commit(self, ticket, desktop, full=False):
        if self.cancel_token() != ticket or self._exists("pending"):
            raise Error("Unlock cancelled")
        if desktop and not self.desktop_gate(full):
            raise Error("Unlock cancelled: desktop locked")

    def _unlock_locked(self, password, desktop, ticket):
        if self.keyring.collection_locked():
            raise Error("Login keyring is locked")
        records, legacy = self._search()
        if records or legacy or self._exists("pending") or self._exists("txn"):
            if not self._cleanup("replace"):
                raise Error("Previous session could not be cleared")
        self._check_commit(ticket, False)
        self._write_json("txn", {"op": "unlock"})
        committed = False
        try:
            token = self._run_unlock(password, lambda: self._cancelled(ticket, desktop))
            self._check_commit(ticket, desktop)
            config = self.config
            now = int(self.clock.wall())
            record = {
                "v": RECORD_VERSION,
                "token": token,
                "generation": secrets.token_hex(4),
                "issued_at": now,
                "deadline": now + config.ttl_seconds,
                "ttl": config.ttl_seconds,
                "boot_id": self.clock.boot_id(),
                "boottime": self.clock.boottime(),
                "slept": self.clock.slept(),
            }
            token = None
            if not record["boot_id"]:
                raise Error("Boot identity unavailable")
            attributes = dict(self._attributes(), generation=record["generation"])
            try:
                self.keyring.create(LABEL, attributes, json.dumps(record).encode("utf-8"))
            except KeyringError:
                raise Error("Session could not be stored") from None
            if not self.timers.arm(record["generation"], record["deadline"]):
                raise Error("Session expiry could not be armed")
            self._check_commit(ticket, desktop, full=True)  # slow D-Bus gate, outside the order lock
            self._remember(f"gen:{record['generation']}", "unlocked")
            with self._commit_order() as ordered:
                if not ordered:
                    raise Error("Unlock cancelled")
                self._check_commit(ticket, desktop)
                self._remove("txn")  # commit point
                committed = True
            return record["generation"]
        finally:
            if not committed:
                # Wrong password, CLI failure or timeout, store/arm failure,
                # cancellation, interruption: the profile may have changed.
                with contextlib.suppress(Exception):
                    self._cleanup("invalid")

    def _run_unlock(self, password, cancelled):
        read_fd, write_fd = os.pipe()
        try:
            try:
                view = memoryview(password + b"\n")
                while view:
                    view = view[os.write(write_fd, view):]
            finally:
                os.close(write_fd)
            rc, document = _bw.run(
                ["unlock", "--passwordfile", f"/dev/fd/{read_fd}"],
                timeout=90, pass_fds=(read_fd,), bw=self.bw, home=self.home, cancelled=cancelled)
        except _bw.Cancelled:
            raise Error("Unlock cancelled") from None
        except _bw.BwFailure:
            raise Error("Bitwarden CLI failed") from None
        finally:
            os.close(read_fd)
        data = (document or {}).get("data") or {}
        token = data.get("raw") if isinstance(data, dict) else None
        if (rc == 0 and document is not None and document.get("success") is True
                and isinstance(token, str) and _TOKEN.match(token)):
            return token
        message = _bw.message_of(document)
        if "not logged in" in message or "no active account" in message:
            raise Error("Not logged in to Bitwarden")
        if document is None or document.get("success") is not False or "key connector" in message:
            raise Error("Unlock failed")
        raise WrongPassword("Wrong master password")

    # -- consumers ---------------------------------------------------------
    def session(self, generation=None):
        """(token, record) for the current committed session, else Expired."""
        self._check_profile()
        if generation is not None and not valid_generation(generation):
            raise Expired(EXPIRED)
        try:
            if not self._recover():
                raise Expired(EXPIRED)
            epoch = self.epoch()
            records, legacy = self._search()
            if legacy or len(records) > 1:
                self.revoke("migrate" if legacy else "invalid")
                raise Expired(EXPIRED)
            if len(records) != 1 or records[0].locked:
                raise Expired(EXPIRED)
            item_generation = self._item_generation(records[0])
            record = self._load(records[0])
        except KeyringError:
            raise Expired(EXPIRED) from None
        if record is None or self.effective_deadline(record) is None:
            self.revoke_generation(item_generation, "expired" if record else "invalid")
            raise Expired(EXPIRED)
        if generation is not None and record["generation"] != generation:
            raise Expired(EXPIRED)
        if record["generation"] != item_generation:
            raise Expired(EXPIRED)
        # Re-read after the keyring round trips: a revocation may have run meanwhile.
        if self.revoked_since(epoch) or self._exists("txn"):
            raise Expired(EXPIRED)
        return record["token"], record

    def run_with_session(self, args, generation=None, timeout=60):
        """Run a session command; returns the parsed `data` of a successful response.

        The child is killed as soon as the session is revoked or reaches its
        deadline, and a result is only returned if the same generation is
        still current afterwards.
        """
        epoch = self.epoch()
        token, record = self.session(generation)
        deadline = self.effective_deadline(record) or 0
        try:
            rc, document = _bw.run(
                args, session=token, timeout=timeout, bw=self.bw, home=self.home,
                cancelled=lambda: self.revoked_since(epoch) or self.clock.wall() >= deadline)
        except _bw.Cancelled:
            raise Expired(EXPIRED) from None
        except _bw.BwFailure:
            raise Error("Bitwarden CLI failed") from None
        finally:
            token = None
        # Discard results produced while the generation changed or expired.
        self.session(record["generation"])
        if self.revoked_since(epoch):
            raise Expired(EXPIRED)
        if rc == 0 and document and document.get("success") is True:
            return document.get("data")
        message = _bw.message_of(document)
        if "locked" in message or "not logged in" in message or "session" in message:
            self.revoke_generation(record["generation"], "invalid")
            raise Expired(EXPIRED)
        if "not found" in message:
            raise Error("Item not found")
        raise Error("Bitwarden CLI failed")

    def meta(self, item_id):
        if not valid_item_id(item_id):
            raise Error("Invalid item id")
        data = self.run_with_session(["get", "item", item_id])
        if not isinstance(data, dict) or data.get("id") != item_id:
            raise Error("Unexpected item data")
        login = data.get("login") if isinstance(data.get("login"), dict) else {}
        username = sanitize(login.get("username"), 200) or None
        uris = []
        for entry in login.get("uris") or []:
            uri = sanitize(entry.get("uri"), 300) if isinstance(entry, dict) else ""
            if uri:
                uris.append(uri)
            if len(uris) >= 10:
                break
        return {"name": sanitize(data.get("name"), 200) or "(unnamed)",
                "username": username, "uris": uris}

    def secret(self, item_id, field, generation):
        if field not in ("password", "username"):
            raise Error("Unsupported field")
        if not valid_item_id(item_id):
            raise Error("Invalid item id")
        data = self.run_with_session(["get", field, item_id], generation=generation)
        value = data.get("data") if isinstance(data, dict) else None
        if not isinstance(value, str):
            raise Error("Field not available")
        return value.encode("utf-8")

    def list_entries(self, generation=None):
        """Ordered [(label, item_id)] with sanitized labels; full items stay here."""
        data = self.run_with_session(["list", "items"], generation=generation, timeout=90)
        items = data.get("data") if isinstance(data, dict) else None
        if not isinstance(items, list):
            raise Error("Unexpected list data")
        entries = []
        for item in items:
            if not isinstance(item, dict) or not valid_item_id(item.get("id")):
                continue
            name = sanitize(item.get("name"), 80) or "(unnamed)"
            login = item.get("login") if isinstance(item.get("login"), dict) else {}
            username = sanitize(login.get("username"), 60)
            label = f"{name} — {username}" if username else name
            entries.append((label, item["id"]))
        del items, data
        entries.sort(key=lambda entry: entry[0].casefold())
        return entries

    # -- expiry, startup, guard ticks ---------------------------------------
    def expire(self, generation):
        """Timer callback: lock only if `generation` is still the committed one.

        Needs the lock; without it nothing changes (returns False, the unit
        fails visibly, readers already deny past the deadline and the guard
        tick retries).  A record that is somehow still valid is left alone.
        """
        if not valid_generation(generation):
            return True
        with self.serialized(15) as acquired:
            if not acquired:
                return False
            if self._exists("pending") or self._exists("txn"):
                return self._cleanup("expired")
            try:
                records, _legacy = self._search()
                current = [item for item in records
                           if self._item_generation(item) in (generation, None)]
            except KeyringError:
                return self._cleanup("expired")
            if not current:
                return True  # stale callback for an older generation
            try:
                record = self._load(current[0]) if len(records) == 1 else None
            except KeyringError:
                record = None
            if record is not None and record["generation"] == generation \
                    and self.effective_deadline(record) is not None:
                return True
            return self._cleanup("expired")

    def reconcile(self):
        """Guard startup: re-arm a valid committed session of this boot, else lock."""
        with self.serialized(15) as acquired:
            if not acquired:
                return False
            try:
                if self._exists("pending") or self._exists("txn"):
                    return self._cleanup("invalid")
                if self.keyring.collection_locked():
                    return self._cleanup("invalid")
                records, legacy = self._search()
                if legacy or len(records) != 1:
                    # No record: unmanaged profile state is locked, never trusted.
                    return self._cleanup("migrate" if legacy else "invalid")
                record = self._load(records[0])
                if record is None or self.effective_deadline(record) is None:
                    return self._cleanup("expired")
                if not self.timers.arm(record["generation"], record["deadline"]):
                    return self._cleanup("invalid")
                return True
            except KeyringError:
                return self._cleanup("invalid")

    def activation_check(self):
        """Non-secret migration facts for the activation script (attributes only)."""
        result = self.status()
        try:
            legacy = len(self.keyring.search({"application": LEGACY_APPLICATION}))
        except KeyringError:
            legacy = None
        return {"state": result["state"], "pending": self._exists("pending"),
                "txn": self._exists("txn"), "legacy_items": legacy}

    def has_records(self):
        try:
            records, legacy = self._search()
        except KeyringError:
            return True  # unknown: treat as present so callers revoke
        return bool(records or legacy)

    def check_expiry(self):
        """Periodic guard tick: finish pending work, revoke invalid or unarmed sessions."""
        try:
            if not self._recover(5):
                return False
            records, legacy = self._search()
            if legacy or len(records) > 1:
                return self.revoke("migrate" if legacy else "invalid")
            if not records or records[0].locked:
                return True
            item_generation = self._item_generation(records[0])
            record = self._load(records[0])
            if record is None or self.effective_deadline(record) is None:
                return self.revoke_generation(item_generation, "expired")
            if not self.timers.is_armed(record["generation"]):
                with self.serialized(5) as acquired:
                    if not acquired:
                        return False
                    if not self.timers.arm(record["generation"], record["deadline"]):
                        return self._cleanup("invalid")
            return True
        except KeyringError:
            return False

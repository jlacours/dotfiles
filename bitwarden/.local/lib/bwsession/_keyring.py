"""Minimal, non-prompting Secret Service client.

Every call has a bounded D-Bus timeout.  This module never calls Unlock and
never executes a Prompt object: when the service answers with a prompt (a
locked collection or item), the prompt is dismissed and KeyringLocked is
raised.  Searching is allowed on locked collections because it only reveals
attributes, never secrets, and does not prompt.

Thread-safety contract: a backend object may be shared by threads.  Every
public operation runs under one re-entrant lock per object, so the blocking
Jeepney connection (which reads replies itself and drops ones it did not ask
for) never sees two requests in flight.  Waiting for that lock is bounded
(LOCK_WAIT, or the caller's deadline) and fails as KeyringUnavailable rather
than blocking a cancellation.  `bounded(deadline)` sets a per-thread deadline
(time.monotonic) that also caps each D-Bus reply timeout.
"""

import contextlib
import functools
import threading
import time

from jeepney import DBusAddress, MessageType, Properties, new_method_call
from jeepney.io.blocking import open_dbus_connection

BUS_NAME = "org.freedesktop.secrets"
SS_PATH = "/org/freedesktop/secrets"
SERVICE_IFACE = "org.freedesktop.Secret.Service"
COLLECTION_IFACE = "org.freedesktop.Secret.Collection"
ITEM_IFACE = "org.freedesktop.Secret.Item"
PROMPT_IFACE = "org.freedesktop.Secret.Prompt"
ALGORITHM_DH = "dh-ietf1024-sha256-aes128-cbc-pkcs7"
ALGORITHM_PLAIN = "plain"
DEFAULT_TIMEOUT = 3.0


class KeyringError(Exception):
    """Backend failure (never carries secret data)."""


class KeyringUnavailable(KeyringError):
    pass


class KeyringLocked(KeyringError):
    pass


class _Bounded:
    """Per-object operation lock and per-thread deadlines (see module docstring)."""

    LOCK_WAIT = 10.0

    def _init_bounded(self):
        self._op_lock = threading.RLock()
        self._local = threading.local()

    @contextlib.contextmanager
    def bounded(self, deadline):
        previous = getattr(self._local, "deadline", None)
        if deadline is None or (previous is not None and previous < deadline):
            deadline = previous
        self._local.deadline = deadline
        try:
            yield
        finally:
            self._local.deadline = previous

    def remaining(self, cap):
        deadline = getattr(self._local, "deadline", None)
        if deadline is None:
            return cap
        left = deadline - time.monotonic()
        if left <= 0:
            raise KeyringUnavailable("out of time")
        return min(cap, left)


def _operation(method):
    @functools.wraps(method)
    def wrapper(self, *args, **kwargs):
        if not self._op_lock.acquire(timeout=self.remaining(self.LOCK_WAIT)):
            raise KeyringUnavailable("keyring busy")
        try:
            return method(self, *args, **kwargs)
        finally:
            self._op_lock.release()
    return wrapper


class Item:
    __slots__ = ("path", "locked")

    def __init__(self, path, locked):
        self.path = path
        self.locked = locked


class SecretServiceKeyring(_Bounded):
    def __init__(self, timeout=DEFAULT_TIMEOUT):
        self._init_bounded()
        self.timeout = timeout
        self._conn = None
        self._session = None

    # -- plumbing ---------------------------------------------------------
    def _connection(self):
        if self._conn is None:
            try:
                self._conn = open_dbus_connection(bus="SESSION")
            except Exception:
                raise KeyringUnavailable("session bus unavailable") from None
        return self._conn

    def _send(self, msg):
        try:
            reply = self._connection().send_and_get_reply(msg, timeout=self.remaining(self.timeout))
        except TimeoutError:
            raise KeyringUnavailable("secret service timed out") from None
        except KeyringError:
            raise
        except Exception:
            raise KeyringUnavailable("secret service call failed") from None
        if reply.header.message_type == MessageType.error:
            name = str(reply.header.fields.get(4, ""))  # HeaderFields.error_name
            if name.endswith("IsLocked"):
                raise KeyringLocked("keyring locked")
            if name.endswith(("ServiceUnknown", "NoReply", "Spawn.ExecFailed")):
                raise KeyringUnavailable("secret service unavailable")
            raise KeyringError("secret service error")
        return reply.body

    def _call(self, path, iface, method, signature=None, *body):
        address = DBusAddress(path, bus_name=BUS_NAME, interface=iface)
        return self._send(new_method_call(address, method, signature, body))

    def _get_property(self, path, iface, name):
        address = DBusAddress(path, bus_name=BUS_NAME, interface=iface)
        (_signature, value), = self._send(Properties(address).get(name))
        return value

    def _dismiss(self, prompt_path):
        try:
            self._call(prompt_path, PROMPT_IFACE, "Dismiss")
        except KeyringError:
            pass

    def _open_session(self):
        if self._session is not None:
            return self._session
        from secretstorage.dhcrypto import Session

        session = Session()
        try:
            output, path = self._call(
                SS_PATH, SERVICE_IFACE, "OpenSession", "sv",
                ALGORITHM_DH, ("ay", session.my_public_key.to_bytes(128, "big")))
            signature, value = output
            if signature != "ay":
                raise KeyringError("unexpected session reply")
            session.set_server_public_key(int.from_bytes(value, "big"))
        except KeyringLocked:
            raise
        except KeyringUnavailable:
            raise
        except KeyringError:
            _output, path = self._call(
                SS_PATH, SERVICE_IFACE, "OpenSession", "sv", ALGORITHM_PLAIN, ("s", ""))
            session.encrypted = False
        session.object_path = path
        self._session = session
        return session

    @_operation
    def close(self):
        if self._conn is not None:
            try:
                self._conn.close()
            except Exception:
                pass
        self._conn = None
        self._session = None

    # -- API --------------------------------------------------------------
    @_operation
    def default_collection(self):
        (path,) = self._call(SS_PATH, SERVICE_IFACE, "ReadAlias", "s", "default")
        if not path or path == "/":
            raise KeyringUnavailable("no default keyring")
        return path

    @_operation
    def collection_locked(self):
        return bool(self._get_property(self.default_collection(), COLLECTION_IFACE, "Locked"))

    @_operation
    def search(self, attributes):
        unlocked, locked = self._call(SS_PATH, SERVICE_IFACE, "SearchItems", "a{ss}", attributes)
        return [Item(p, False) for p in unlocked] + [Item(p, True) for p in locked]

    @_operation
    def get_secret(self, item):
        if item.locked:
            raise KeyringLocked("item locked")
        session = self._open_session()
        (secret,) = self._call(item.path, ITEM_IFACE, "GetSecret", "o", session.object_path)
        if not session.encrypted:
            return bytes(secret[2])
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

        decryptor = Cipher(algorithms.AES(session.aes_key), modes.CBC(bytes(secret[1]))).decryptor()
        padded = decryptor.update(bytes(secret[2])) + decryptor.finalize()
        if not padded or padded[-1] < 1 or padded[-1] > 16:
            raise KeyringError("bad secret padding")
        return padded[:-padded[-1]]

    @_operation
    def create(self, label, attributes, secret):
        collection = self.default_collection()
        if self._get_property(collection, COLLECTION_IFACE, "Locked"):
            raise KeyringLocked("keyring locked")
        session = self._open_session()
        if session.encrypted:
            from secretstorage.util import format_secret

            formatted = format_secret(session, secret, "application/json")
        else:
            formatted = (session.object_path, b"", secret, "application/json")
        properties = {
            ITEM_IFACE + ".Label": ("s", label),
            ITEM_IFACE + ".Attributes": ("a{ss}", attributes),
        }
        item_path, prompt = self._call(
            collection, COLLECTION_IFACE, "CreateItem", "a{sv}(oayays)b",
            properties, formatted, True)
        if prompt and prompt != "/":
            self._dismiss(prompt)
            raise KeyringLocked("keyring locked")
        if not item_path or item_path == "/":
            raise KeyringError("item not created")
        return item_path

    @_operation
    def item_generation(self, item):
        """Non-secret `generation` attribute (readable on locked items)."""
        attributes = self._get_property(item.path, ITEM_IFACE, "Attributes")
        generation = attributes.get("generation") if isinstance(attributes, dict) else None
        return generation if isinstance(generation, str) else None

    @_operation
    def delete(self, item):
        if item.locked:
            raise KeyringLocked("item locked")
        (prompt,) = self._call(item.path, ITEM_IFACE, "Delete")
        if prompt and prompt != "/":
            self._dismiss(prompt)
            raise KeyringLocked("keyring locked")


class MemoryKeyring(_Bounded):
    """In-process stand-in used by tests (same interface and locking)."""

    def __init__(self):
        self._init_bounded()
        self.items = {}
        self.locked = False
        self.unavailable = False
        self.fail_create = False
        self.fail_delete = False
        self._counter = 0

    def _check(self):
        if self.unavailable:
            raise KeyringUnavailable("unavailable")

    @_operation
    def default_collection(self):
        self._check()
        return "/memory/default"

    @_operation
    def collection_locked(self):
        self._check()
        return self.locked

    @_operation
    def search(self, attributes):
        self._check()
        return [Item(path, self.locked) for path, (attrs, _secret) in self.items.items()
                if all(attrs.get(k) == v for k, v in attributes.items())]

    @_operation
    def get_secret(self, item):
        self._check()
        if self.locked:
            raise KeyringLocked("locked")
        return self.items[item.path][1]

    @_operation
    def create(self, label, attributes, secret):
        self._check()
        if self.locked:
            raise KeyringLocked("locked")
        if self.fail_create:
            raise KeyringError("create failed")
        for path, (attrs, _secret) in list(self.items.items()):
            if attrs == attributes:
                del self.items[path]
        self._counter += 1
        path = f"/memory/{self._counter}"
        self.items[path] = (dict(attributes), bytes(secret))
        return path

    @_operation
    def item_generation(self, item):
        self._check()
        return self.items[item.path][0].get("generation")

    @_operation
    def delete(self, item):
        self._check()
        if self.locked:
            raise KeyringLocked("locked")
        if self.fail_delete:
            raise KeyringError("delete failed")
        self.items.pop(item.path, None)

    @_operation
    def close(self):
        pass

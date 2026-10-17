"""Fake session authority used by isolated TUI contract tests only."""

from __future__ import annotations

import time
import os
import secrets
import threading

STATE = "unlocked"
GENERATION = "a1b2c3d4"
CANCEL_TOKEN = "0123456789abcdef"
DESKTOP_UNLOCKED = True
CALLS: list[tuple[object, ...]] = []
_METRICS_LOCK = threading.Lock()
ACTIVE_CALLS = 0
MAX_ACTIVE_CALLS = 0
OVERLAP = threading.Event()
BLOCK_METHOD: str | None = None
BLOCK_STARTED = threading.Event()
BLOCK_RELEASE = threading.Event()
CANCELLED = threading.Event()


class Error(Exception):
    pass


class WrongPassword(Error):
    pass


class Expired(Error):
    pass


class _TrackedCall:
    def __init__(self, name: str) -> None:
        self.name = name

    def __enter__(self):
        global ACTIVE_CALLS, MAX_ACTIVE_CALLS
        with _METRICS_LOCK:
            ACTIVE_CALLS += 1
            MAX_ACTIVE_CALLS = max(MAX_ACTIVE_CALLS, ACTIVE_CALLS)
            if ACTIVE_CALLS > 1:
                OVERLAP.set()
        if BLOCK_METHOD == self.name:
            BLOCK_STARTED.set()
            while not BLOCK_RELEASE.wait(0.01):
                if os.environ.get("FAKE_BACKEND_BLOCK_FOREVER") == "1":
                    continue
        return self

    def __exit__(self, *_exc):
        global ACTIVE_CALLS
        with _METRICS_LOCK:
            ACTIVE_CALLS -= 1


def reset_metrics():
    global ACTIVE_CALLS, MAX_ACTIVE_CALLS, BLOCK_METHOD
    with _METRICS_LOCK:
        ACTIVE_CALLS = 0
        MAX_ACTIVE_CALLS = 0
    OVERLAP.clear()
    BLOCK_STARTED.clear()
    BLOCK_RELEASE.clear()
    CANCELLED.clear()
    BLOCK_METHOD = None


def status():
    with _TrackedCall("status"):
        return {
            "schema": 1,
            "state": STATE,
            "deadline": int(time.time()) + 3600 if STATE == "unlocked" else None,
            "generation": GENERATION if STATE == "unlocked" else None,
            "message": "fixed test state",
        }


def meta(item_id):
    with _TrackedCall("meta"):
        CALLS.append(("meta", item_id))
        return {
            "name": "Example <item>",
            "username": "user@example.test",
            "uris": ["https://example.test/"],
        }


def secret(item_id, field, generation):
    with _TrackedCall("secret"):
        CALLS.append(("secret", item_id, field, generation))
        if os.environ.get("FAKE_SECRET_HANG") == "1":
            while True:
                time.sleep(1)
        if generation != GENERATION or STATE != "unlocked":
            raise Expired
        return b"synthetic-test-value"


def unlock_ticket():
    CALLS.append(("unlock_ticket", CANCEL_TOKEN))
    return CANCEL_TOKEN


def unlock(password, desktop=True, ticket=None):
    global STATE, GENERATION
    with _TrackedCall("unlock"):
        if ticket is None:
            ticket = unlock_ticket()
        CALLS.append(("unlock", bytes(password), desktop, ticket))
        if ticket != CANCEL_TOKEN:
            raise Error("synthetic unlock canceled")
        if os.environ.get("FAKE_UNLOCK_HANG") == "1":
            if os.environ.get("FAKE_UNLOCK_COMMIT_BEFORE_CANCEL") == "1":
                STATE = "unlocked"
                GENERATION = "c0ffee12"
                while not CANCELLED.wait(0.01):
                    pass
                return GENERATION
            while not CANCELLED.wait(0.01):
                pass
            raise Error("synthetic unlock canceled")
        if desktop and not DESKTOP_UNLOCKED:
            raise Error("desktop locked before commit")
        if password != b"test-password":
            raise WrongPassword
        STATE = "unlocked"
        return GENERATION


def lock_generation(generation, reason="manual"):
    global STATE
    with _TrackedCall("lock_generation"):
        CALLS.append(("lock_generation", generation, reason))
        if os.environ.get("FAKE_LOCK_GENERATION_FAIL") == "1":
            raise Error("synthetic generation revoke failure")
        if STATE == "unlocked" and generation == GENERATION:
            STATE = "locked"
        logfile = os.environ.get("FAKE_LOCK_GENERATION_LOG")
        if logfile:
            with open(logfile, "a", encoding="utf-8") as handle:
                handle.write(f"{generation}\n")


def cancel_unlocks():
    global CANCEL_TOKEN
    CALLS.append(("cancel_unlocks",))
    CANCEL_TOKEN = secrets.token_hex(8)
    CANCELLED.set()


def desktop_unlocked():
    return DESKTOP_UNLOCKED


def lock(reason="manual"):
    global STATE, DESKTOP_UNLOCKED
    CALLS.append(("lock", reason))
    STATE = "locked"
    DESKTOP_UNLOCKED = False

"""Bitwarden metadata card; secrets are fetched only after explicit copy."""

from __future__ import annotations

import os
import sys
import threading
from collections.abc import Iterable
from typing import Any

from .clipboard import (
    SENSITIVE_CLIPBOARD_VERIFIED,
    copy,
    kill_owned_clipboards,
)
from .security import apply_process_hardening, clear_textual_debug_environment, sanitize_display
from .session import (
    SessionError,
    SessionExpired,
    SessionBusy,
    SessionCancelled,
    item_meta,
    item_secret,
    require_unlocked,
    validate_generation,
    validate_item_id,
)
from .floating import FloatingLaunchError, FOOT_TTY_MARKER, launch_floating, terminal_route

_PASSWORD_MASK = "••••••••"
_GENERATION_CHANGED_MESSAGE = "Bitwarden session changed; reopen the item."
_USAGE_MESSAGE = "Usage: bw-card ITEM_ID [--generation GENERATION]"
_TERMINAL_MESSAGE = "Bitwarden card requires its dedicated Foot terminal."
_MAX_CONSECUTIVE_BUSY_POLLS = 2


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    try:
        apply_process_hardening()
    except Exception:
        return _fail("Unable to secure the Bitwarden card.")
    clear_textual_debug_environment()
    os.environ.pop("BW_SESSION", None)
    os.environ["BW_NOINTERACTION"] = "true"
    marker = os.environ.pop(FOOT_TTY_MARKER, None)
    route = terminal_route(marker)
    if route == "launch":
        try:
            from pathlib import Path

            launcher = Path.home() / ".local" / "bin" / "bw-card"
            return launch_floating([str(launcher), *args], wait=True)
        except FloatingLaunchError:
            return _fail("Unable to start the Bitwarden card window.")
    if route != "inline":
        return _fail(_TERMINAL_MESSAGE)
    try:
        item_id, requested_generation = _parse_args(args)
    except SessionError:
        return _fail(_USAGE_MESSAGE)
    try:
        initial = require_unlocked()
    except SessionError:
        return _fail("Bitwarden is locked or unavailable.")
    initial_generation = str(initial["generation"])
    if requested_generation is not None and initial_generation != requested_generation:
        return _fail(_GENERATION_CHANGED_MESSAGE)

    try:
        CardApp, widgets = _base()
        require_unlocked(initial_generation)
        metadata = item_meta(item_id)
        require_unlocked(initial_generation)
    except SessionExpired:
        return _fail(_GENERATION_CHANGED_MESSAGE)
    except SessionError:
        return _fail("Bitwarden is locked or unavailable.")
    except Exception as exc:
        if type(exc).__name__ == "TextualUnavailable":
            return _fail("Textual is required for Bitwarden cards.")
        return _fail("Unable to load this item.")

    Binding = widgets["Binding"]
    Button = widgets["Button"]
    ButtonBar = widgets["ButtonBar"]
    FieldRow = widgets["FieldRow"]
    Header = widgets["Header"]
    HintBar = widgets["HintBar"]
    StatusLine = widgets["StatusLine"]

    class BitwardenCard(CardApp):
        BINDINGS = CardApp.BINDINGS + [
            Binding("u", "copy_username", "Copy username", show=False, priority=True),
            Binding("p", "copy_password", "Copy password", show=False, priority=True),
        ]

        def __init__(self) -> None:
            self._card_dismissing = False
            self._status_busy = False
            self._status_busy_polls = 0
            self._status_worker = None
            self._status_cancel = None
            self._session_timer = None
            self._copy_busy = False
            self._copy_worker = None
            self._copy_cancel = None
            self._last_copy_sensitive = False
            super().__init__()

        def compose_contents(self) -> Iterable[Any]:
            name = sanitize_display(metadata["name"], limit=80) or "Unnamed item"
            yield Header("◆", name)
            with widgets["Container"](id="field-list"):
                username = metadata["username"]
                yield FieldRow(
                    "Username",
                    sanitize_display(username) if username else "Not set",
                )
                yield FieldRow("Password", _PASSWORD_MASK)
                for uri in metadata["uris"]:
                    yield FieldRow(
                        "Website",
                        sanitize_display(uri, limit=512) or "(empty)",
                    )
            username = metadata["username"]
            with ButtonBar(id="buttons"):
                yield Button(
                    "Copy user  (u)",
                    id="copy_username",
                    disabled=username is None,
                )
                yield Button(
                    "Copy pass  (p)",
                    id="copy_password",
                    disabled=not SENSITIVE_CLIPBOARD_VERIFIED,
                )
                yield Button("Close  (esc)", id="close")
            yield StatusLine()
            yield HintBar("u copy user · p copy pass · esc close")

        def on_mount(self) -> None:
            super().on_mount()
            self._session_timer = self.set_interval(2.0, self._check_session)

        def _check_session(self) -> None:
            if self._card_dismissing or self._status_busy:
                return
            self._status_busy = True
            cancel_event = threading.Event()
            self._status_cancel = cancel_event
            worker = self.run_backend_worker(
                self._session_in_thread,
                initial_generation,
                cancel_event,
                name="session-status",
                group="session-status",
            )
            self._status_worker = worker
            self.watch_worker(worker, self._session_ok, self._session_failed)

        @staticmethod
        def _session_in_thread(generation: str, cancel_event: threading.Event) -> Any:
            try:
                return require_unlocked(generation, cancel_event=cancel_event)
            except SessionBusy:
                return "busy"
            except SessionCancelled:
                return "cancelled"

        def _session_ok(self, result: Any) -> None:
            self._status_busy = False
            self._status_worker = None
            if self._card_dismissing:
                return
            if result == "busy":
                self._status_busy_polls += 1
                if self._status_busy_polls >= _MAX_CONSECUTIVE_BUSY_POLLS:
                    self.action_close()
                return
            if result == "cancelled":
                return
            self._status_busy_polls = 0

        def _session_failed(self) -> None:
            self._status_busy = False
            self._status_worker = None
            if not self._card_dismissing:
                self.action_close()

        def on_button_pressed(self, event: Any) -> None:
            super().on_button_pressed(event)
            if event.button.id == "close":
                self.action_close()
            elif event.button.id == "copy_username":
                self.action_copy_username()
            elif event.button.id == "copy_password":
                self.action_copy_password()

        def action_copy_username(self) -> None:
            self._copy_field("username", sensitive=False)

        def action_copy_password(self) -> None:
            if SENSITIVE_CLIPBOARD_VERIFIED:
                self._copy_field("password", sensitive=True)

        def _copy_field(self, field: str, *, sensitive: bool) -> None:
            if self._card_dismissing or self._copy_busy:
                return
            self._copy_busy = True
            self._last_copy_sensitive = sensitive
            self._copy_cancel = threading.Event()
            self.query_one("#copy_username", Button).disabled = True
            self.query_one("#copy_password", Button).disabled = True
            worker = self.run_backend_worker(
                self._copy_in_thread,
                field,
                sensitive,
                self._copy_cancel,
                name="copy-secret",
                group="copy-secret",
            )
            self._copy_worker = worker
            self.watch_worker(worker, self._copy_finished, self._copy_failed)

        @staticmethod
        def _copy_in_thread(
            field: str, sensitive: bool, cancel_event: threading.Event
        ) -> str:
            try:
                data = item_secret(
                    item_id,
                    field,
                    initial_generation,
                    cancel_event=cancel_event,
                )
            except SessionBusy:
                return "busy"
            except SessionCancelled:
                return "cancelled"
            except SessionError:
                return "locked"
            try:
                if cancel_event.is_set():
                    return "cancelled"
                copy(
                    data,
                    sensitive=sensitive,
                    ttl=30,
                    expected_generation=initial_generation,
                    cancel_event=cancel_event,
                )
                return "copied"
            except Exception:
                # ClipboardError can wrap a generation mismatch detected while
                # starting the supervisor. Fail closed if the session moved.
                try:
                    require_unlocked(initial_generation)
                except SessionError:
                    return "locked"
                return "failed"
            finally:
                del data

        def _copy_finished(self, outcome: str) -> None:
            self._copy_worker = None
            self._copy_busy = False
            if self._card_dismissing:
                return
            if outcome == "locked":
                self.action_close()
                return
            self.query_one("#copy_username", Button).disabled = metadata["username"] is None
            self.query_one("#copy_password", Button).disabled = not SENSITIVE_CLIPBOARD_VERIFIED
            if outcome != "copied":
                if outcome == "cancelled":
                    return
                self.query_one(StatusLine).show_message(
                    "Unable to copy this item.", error=True
                )
                return
            label = "Password copied" if self._last_copy_sensitive else "Username copied"
            self.query_one(StatusLine).show_countdown(label, 30)

        def _copy_failed(self) -> None:
            self._copy_worker = None
            self._copy_busy = False
            if self._card_dismissing:
                return
            # An unexpected worker failure leaves the session state uncertain.
            self.action_close()

        def action_close(self) -> None:
            if self._card_dismissing:
                return
            self._card_dismissing = True
            if getattr(self, "_status_cancel", None) is not None:
                self._status_cancel.set()
            if self._status_worker is not None:
                self._status_worker.cancel()
            if self._copy_cancel is not None:
                self._copy_cancel.set()
            if self._copy_worker is not None:
                self._copy_worker.cancel()
            kill_owned_clipboards()
            self.exit()

    try:
        return _run(BitwardenCard())
    except Exception:
        return _fail("Unable to open this item.")


def _base() -> tuple[type[Any], dict[str, Any]]:
    from .base import create_card_app_class

    return create_card_app_class()


def _parse_args(args: list[str]) -> tuple[str, str | None]:
    if len(args) == 1:
        return validate_item_id(args[0]), None
    if len(args) == 3 and args[1] == "--generation":
        return validate_item_id(args[0]), validate_generation(args[2])
    raise SessionError


def _run(app: Any) -> int:
    from .base import run_card

    return run_card(app)


def _fail(message: str) -> int:
    try:
        os.write(2, (message + "\n").encode("utf-8"))
    except OSError:
        pass
    return 2

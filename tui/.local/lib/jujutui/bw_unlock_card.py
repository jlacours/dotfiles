"""Deliberately initiated, single-instance Bitwarden unlock card.

Exit codes: 0 means the unlock succeeded; 1 means a runtime error; 2 means a
setup or usage error; 3 means the user canceled or dismissed the card; 4 means
another unlock card is already running.
"""

from __future__ import annotations

import datetime as dt
import os
import subprocess
import sys
import threading
from collections.abc import Iterable
from typing import Any

from .security import apply_process_hardening, clear_textual_debug_environment
from .session import (
    SessionCancelled,
    SessionError,
    SessionWrongPassword,
    cancel_unlocks,
    desktop_unlocked,
    lock_generation,
    status_snapshot,
    unlock_ticket,
    unlock_session,
)
from .floating import (
    FloatingLaunchError,
    FOOT_TTY_MARKER,
    launch_floating,
    terminal_route,
)

_UNLOCK_CANCEL_TIMEOUT_SECONDS = 32.0
_UNLOCK_SHUTDOWN_GRACE_SECONDS = 16.0


class _CancelExitCode:
    """Thread-safe target status for an abandoned unlock attempt."""

    def __init__(self) -> None:
        self._value = 3
        self._lock = threading.Lock()

    def set(self, value: int) -> None:
        with self._lock:
            self._value = value

    def get(self) -> int:
        with self._lock:
            return self._value


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    try:
        apply_process_hardening()
    except Exception:
        return _fail("Unable to secure the unlock card.")
    clear_textual_debug_environment()
    os.environ.pop("BW_SESSION", None)
    os.environ["BW_NOINTERACTION"] = "true"
    marker = os.environ.pop(FOOT_TTY_MARKER, None)
    if args:
        return _fail("Usage: bw-unlock-card")
    route = terminal_route(marker)
    if route == "launch":
        try:
            from pathlib import Path

            launcher = Path.home() / ".local" / "bin" / "bw-unlock-card"
            return launch_floating([str(launcher)], wait=True)
        except FloatingLaunchError:
            return _fail("Unable to start the Bitwarden unlock window.")
    if route != "inline":
        return _fail("Bitwarden card requires its dedicated Foot terminal.")
    if not desktop_unlocked():
        return 3
    try:
        from .instance import acquire_unlock_card_lock

        lock_fd = acquire_unlock_card_lock()
    except Exception as exc:
        if type(exc).__name__ == "InstanceAlreadyRunning":
            return 4
        return _fail("Unable to open the unlock card.")

    try:
        try:
            CardApp, widgets = _base()
        except Exception as exc:
            if type(exc).__name__ == "TextualUnavailable":
                return _fail("Textual is required for Bitwarden cards.")
            return _fail("Unable to open the unlock card.")

        Button = widgets["Button"]
        ButtonBar = widgets["ButtonBar"]
        Container = widgets["Container"]
        FieldRow = widgets["FieldRow"]
        Header = widgets["Header"]
        HintBar = widgets["HintBar"]
        Input = widgets["PasswordInput"]
        StatusLine = widgets["StatusLine"]

        class UnlockCard(CardApp):
            def __init__(self) -> None:
                self._busy = False
                self._card_dismissing = False
                self._dismiss_requested = False
                self._dismiss_exit_code = _CancelExitCode()
                self._unlock_cancel = None
                self._unlock_worker = None
                self._cancel_revoke_worker = None
                self._unlock_revocation_pending = threading.Event()
                self._cancel_timeout = None
                self._desktop_busy = False
                self._desktop_worker = None
                self._ttl = _ttl_label()
                super().__init__()

            def compose_contents(self) -> Iterable[Any]:
                yield Header("▣", "Unlock Bitwarden")
                with Container(id="field-list"):
                    yield FieldRow("Session", self._ttl)
                    yield Input(
                        placeholder="Master password",
                        password=True,
                        id="master-password",
                    )
                with ButtonBar(id="buttons"):
                    yield Button("Unlock  (enter)", id="unlock")
                    yield Button("Close  (esc)", id="close")
                yield StatusLine()
                yield HintBar("enter unlock · esc close")

            def on_mount(self) -> None:
                super().on_mount()
                self.query_one("#master-password", Input).focus()
                self._desktop_timer = self.set_interval(2.0, self._check_desktop)

            def on_input_changed(self, event: Any) -> None:
                self._reset_inactivity()
                status = self.query_one(StatusLine)
                if event.value and status.has_class("error"):
                    status.clear_message()

            def on_input_submitted(self, _event: Any) -> None:
                self._unlock()

            def on_button_pressed(self, event: Any) -> None:
                super().on_button_pressed(event)
                if event.button.id == "close":
                    self.action_close()
                elif event.button.id == "unlock":
                    self._unlock()

            def action_close(self) -> None:
                """Report Esc/q/Close (and inactivity dismissal) distinctly."""
                if self._card_dismissing or self._dismiss_requested:
                    return
                if self._busy:
                    self._request_unlock_cancellation(
                        "Unable to cancel unlock safely; try closing again.",
                        exit_code=3,
                    )
                    return
                self._finish_dismissal(3)

            def _request_unlock_cancellation(
                self, failure_message: str, *, exit_code: int
            ) -> None:
                try:
                    cancel_unlocks()
                except SessionError:
                    self._reset_inactivity()
                    self._set_message(failure_message, error=True)
                    return
                self._dismiss_requested = True
                self._dismiss_exit_code.set(exit_code)
                if self._unlock_cancel is not None:
                    self._unlock_cancel.set()
                if self._desktop_worker is not None:
                    self._desktop_worker.cancel()
                from .base import extend_backend_shutdown

                extend_backend_shutdown(
                    _UNLOCK_SHUTDOWN_GRACE_SECONDS,
                    timeout_exit_code=1,
                )
                self._cancel_timeout = self.set_timer(
                    _UNLOCK_CANCEL_TIMEOUT_SECONDS,
                    self._unlock_cancellation_timed_out,
                )
                self._set_message("Canceling unlock safely…")

            def _unlock_cancellation_timed_out(self) -> None:
                if not self._dismiss_requested or self._card_dismissing:
                    return
                from .base import extend_backend_shutdown, set_backend_exit_status

                set_backend_exit_status(1)
                extend_backend_shutdown(
                    _UNLOCK_SHUTDOWN_GRACE_SECONDS,
                    timeout_exit_code=1,
                )
                self._finish_dismissal(1)

            def _finish_dismissal(self, exit_code: int) -> None:
                if self._card_dismissing:
                    return
                self._card_dismissing = True
                if self._cancel_timeout is not None:
                    self._cancel_timeout.stop()
                    self._cancel_timeout = None
                if self._desktop_worker is not None:
                    self._desktop_worker.cancel()
                from .base import set_backend_exit_status

                set_backend_exit_status(exit_code)
                self.exit(return_code=exit_code)

            def _set_message(self, message: str, *, error: bool = False) -> None:
                self.query_one(StatusLine).show_message(message, error=error)

            def _unlock(self) -> None:
                if self._busy or self._card_dismissing:
                    return
                password_input = self.query_one("#master-password", Input)
                password = password_input.value
                if not password:
                    self._set_message("Enter your master password to continue.")
                    password_input.focus()
                    return
                password_input.value = ""
                password_bytes = password.encode("utf-8")
                del password
                try:
                    ticket = unlock_ticket()
                except SessionError:
                    del password_bytes
                    self._set_message("Unable to start unlock safely.", error=True)
                    password_input.focus()
                    return
                self._busy = True
                password_input.disabled = True
                self.query_one("#unlock", Button).disabled = True
                self._unlock_cancel = threading.Event()
                self._dismiss_exit_code = _CancelExitCode()
                worker = self.run_backend_worker(
                    self._unlock_in_thread,
                    password_bytes,
                    self._unlock_cancel,
                    ticket,
                    self._dismiss_exit_code,
                    self._unlock_revocation_pending,
                    name="unlock-session",
                    group="unlock-session",
                )
                self._unlock_worker = worker
                self.watch_worker(worker, self._unlock_finished, self._unlock_failed)

            @staticmethod
            def _unlock_in_thread(
                password_bytes: bytes,
                cancel_event: threading.Event,
                ticket: str,
                cancel_exit_code: _CancelExitCode,
                revocation_pending: threading.Event,
            ) -> tuple[str, int | None, str | None]:
                try:
                    try:
                        generation = unlock_session(
                            password_bytes,
                            ticket,
                            cancel_event=cancel_event,
                        )
                    except SessionCancelled:
                        from .base import set_backend_exit_status

                        if cancel_event.is_set():
                            set_backend_exit_status(cancel_exit_code.get())
                        return "cancelled", None, None
                    except SessionWrongPassword:
                        if cancel_event.is_set():
                            from .base import set_backend_exit_status

                            set_backend_exit_status(cancel_exit_code.get())
                            return "cancelled", None, None
                        return "wrong", None, None
                    except Exception as exc:
                        if cancel_event.is_set():
                            from .base import set_backend_exit_status

                            set_backend_exit_status(cancel_exit_code.get())
                            return "cancelled", None, None
                        if not desktop_unlocked():
                            return "cancelled", None, None
                        return (
                            "error",
                            None,
                            None,
                        )
                    if cancel_event.is_set():
                        return UnlockCard._revoke_abandoned_generation(
                            generation,
                            cancel_exit_code,
                            revocation_pending,
                        )
                    deadline = _unlocked_deadline()
                    if cancel_event.is_set():
                        return UnlockCard._revoke_abandoned_generation(
                            generation,
                            cancel_exit_code,
                            revocation_pending,
                        )
                    if deadline is None:
                        return "status-error", None, generation
                    _send_success_toast(deadline)
                    return "success", deadline, generation
                finally:
                    del password_bytes

            @staticmethod
            def _revoke_abandoned_generation(
                generation: str,
                cancel_exit_code: _CancelExitCode,
                revocation_pending: threading.Event,
            ) -> tuple[str, int | None, str | None]:
                from .base import set_backend_exit_status

                revocation_pending.set()
                try:
                    lock_generation(generation)
                except SessionError:
                    set_backend_exit_status(1)
                    return "revocation-failed", None, generation
                finally:
                    revocation_pending.clear()
                set_backend_exit_status(cancel_exit_code.get())
                return "cancelled", None, None

            def _unlock_finished(
                self, result: tuple[str, int | None, str | None]
            ) -> None:
                self._unlock_worker = None
                kind, deadline, generation = result
                if self._dismiss_requested:
                    if kind == "revocation-failed":
                        self._finish_dismissal(1)
                    elif generation is not None:
                        self._start_dismissal_revocation(generation)
                    else:
                        self._finish_dismissal(self._dismiss_exit_code.get())
                    return
                if self._card_dismissing:
                    return
                if kind == "success" and deadline is not None:
                    self._card_dismissing = True
                    self.exit(return_code=0)
                    return
                if kind == "cancelled":
                    self._finish_dismissal(3)
                    return
                if kind == "revocation-failed":
                    self._finish_dismissal(1)
                    return
                if kind == "wrong":
                    self._set_message("Password not accepted. Try again.", error=True)
                elif kind == "status-error":
                    self._set_message(
                        "Unlocked, but session status is unavailable.", error=True
                    )
                else:
                    self._set_message("Unable to unlock Bitwarden.", error=True)
                self._unlock_retry()

            def _start_dismissal_revocation(self, generation: str) -> None:
                self._unlock_revocation_pending.set()
                worker = self.run_backend_worker(
                    self._revoke_abandoned_generation,
                    generation,
                    self._dismiss_exit_code,
                    self._unlock_revocation_pending,
                    name="revoke-abandoned-unlock",
                    group="unlock-session",
                )
                self._cancel_revoke_worker = worker
                self.watch_worker(
                    worker,
                    self._dismissal_revocation_finished,
                    self._dismissal_revocation_failed,
                )

            def _dismissal_revocation_finished(self, _result: Any) -> None:
                self._cancel_revoke_worker = None
                self._finish_dismissal(self._dismiss_exit_code.get())

            def _dismissal_revocation_failed(self) -> None:
                self._cancel_revoke_worker = None
                self._finish_dismissal(1)

            def _unlock_failed(self) -> None:
                self._unlock_worker = None
                if self._dismiss_requested:
                    self._finish_dismissal(1)
                    return
                if not self._card_dismissing:
                    self._set_message("Unable to unlock Bitwarden.", error=True)
                    self._unlock_retry()

            def _unlock_retry(self) -> None:
                self._busy = False
                password_input = self.query_one("#master-password", Input)
                password_input.disabled = False
                self.query_one("#unlock", Button).disabled = False
                password_input.focus()

            def _check_desktop(self) -> None:
                if self._card_dismissing or self._desktop_busy:
                    return
                self._desktop_busy = True
                worker = self.run_backend_worker(
                    desktop_unlocked,
                    name="desktop-unlocked",
                    group="desktop-unlocked",
                )
                self._desktop_worker = worker
                self.watch_worker(worker, self._desktop_checked, self._desktop_failed)

            def _desktop_checked(self, unlocked: bool) -> None:
                self._desktop_busy = False
                self._desktop_worker = None
                if not unlocked and not self._card_dismissing:
                    self._desktop_locked()

            def _desktop_failed(self) -> None:
                self._desktop_busy = False
                self._desktop_worker = None
                if not self._card_dismissing:
                    self._desktop_locked()

            def _desktop_locked(self) -> None:
                if self._card_dismissing or self._dismiss_requested:
                    return
                if self._busy:
                    self._request_unlock_cancellation(
                        "Unable to cancel unlock safely; the desktop is locked.",
                        exit_code=3,
                    )
                    return
                self._finish_dismissal(3)

            def _handle_exception(self, error: Exception) -> None:
                if self._busy:
                    try:
                        cancel_unlocks()
                    except SessionError:
                        pass
                    if self._unlock_cancel is not None:
                        self._unlock_cancel.set()
                    self._dismiss_requested = True
                    self._dismiss_exit_code.set(1)
                    from .base import extend_backend_shutdown

                    extend_backend_shutdown(
                        _UNLOCK_SHUTDOWN_GRACE_SECONDS,
                        timeout_exit_code=1,
                    )
                if self._desktop_worker is not None:
                    self._desktop_worker.cancel()
                super()._handle_exception(error)

        return _run(UnlockCard())
    except Exception:
        return _fail("Unable to open the unlock card.")
    finally:
        os.close(lock_fd)


def _ttl_label() -> str:
    from .config import configured_ttl_hours

    hours = configured_ttl_hours()
    if hours is None:
        return "Lifetime unavailable; unlock policy may reject this request."
    suffix = "hour" if hours == 1 else "hours"
    return f"Expires after up to {hours} {suffix}; use does not renew the deadline."


def _unlocked_deadline() -> int | None:
    try:
        snapshot = status_snapshot()
    except SessionError:
        return None
    deadline = snapshot["deadline"]
    if snapshot["state"] != "unlocked" or not isinstance(deadline, int):
        return None
    return deadline


def _send_success_toast(deadline: int) -> None:
    try:
        until = dt.datetime.fromtimestamp(deadline).astimezone().strftime("%H:%M")
    except (OverflowError, OSError, ValueError):
        return
    env = os.environ.copy()
    env.pop("BW_SESSION", None)
    env["BW_NOINTERACTION"] = "true"
    try:
        subprocess.run(
            ["notify-send", "Bitwarden", f"Unlocked until {until}"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
            check=False,
            timeout=2,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def _base() -> tuple[type[Any], dict[str, Any]]:
    from .base import create_card_app_class

    return create_card_app_class()


def _run(app: Any) -> int:
    from .base import run_card

    return run_card(app)


def _fail(message: str) -> int:
    try:
        os.write(2, (message + "\n").encode("utf-8"))
    except OSError:
        pass
    return 2

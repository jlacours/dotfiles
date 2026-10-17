"""Shared Textual card shell. Textual is imported only after env hardening."""

from __future__ import annotations

import asyncio
import os
import sys
import threading
import time
from collections.abc import Iterable
from typing import Any

from .clipboard import kill_owned_clipboards
from .security import clear_textual_debug_environment, wallust_palette


class TextualUnavailable(RuntimeError):
    """Textual is not installed in the current Python environment."""


_BACKEND_THREADS: set[threading.Thread] = set()
_BACKEND_THREADS_LOCK = threading.Lock()
_BACKEND_SHUTDOWN_GRACE = 0.5
_BACKEND_TIMEOUT_EXIT_CODE = 1
_BACKEND_EXIT_STATUS: int | None = None


def extend_backend_shutdown(grace: float, *, timeout_exit_code: int = 1) -> None:
    """Give an abandoned unlock time to finish bounded W cancellation/revocation."""
    global _BACKEND_SHUTDOWN_GRACE, _BACKEND_TIMEOUT_EXIT_CODE
    if not isinstance(grace, (int, float)) or grace < 0:
        raise ValueError("invalid backend shutdown grace")
    with _BACKEND_THREADS_LOCK:
        _BACKEND_SHUTDOWN_GRACE = max(_BACKEND_SHUTDOWN_GRACE, float(grace))
        _BACKEND_TIMEOUT_EXIT_CODE = timeout_exit_code


def set_backend_exit_status(exit_code: int) -> None:
    """Set a confirmed unlock-dismissal status from its daemon worker."""
    global _BACKEND_EXIT_STATUS
    if isinstance(exit_code, int) and 0 <= exit_code <= 255:
        with _BACKEND_THREADS_LOCK:
            _BACKEND_EXIT_STATUS = exit_code


def _deliver_backend_result(
    future: asyncio.Future[Any], value: Any = None, error: BaseException | None = None
) -> None:
    if future.done():
        return
    if error is None:
        future.set_result(value)
    else:
        future.set_exception(error)


async def _run_daemon_backend(function: Any, *args: Any, **kwargs: Any) -> Any:
    """Run blocking backend work without tying process exit to executor shutdown."""
    loop = asyncio.get_running_loop()
    result = loop.create_future()

    def invoke() -> None:
        try:
            value = function(*args, **kwargs)
        except BaseException as error:
            delivery = (None, error)
        else:
            delivery = (value, None)
        finally:
            with _BACKEND_THREADS_LOCK:
                _BACKEND_THREADS.discard(threading.current_thread())
        try:
            loop.call_soon_threadsafe(
                _deliver_backend_result, result, delivery[0], delivery[1]
            )
        except RuntimeError:
            # The card process is exiting and the event loop is already gone.
            pass

    thread = threading.Thread(
        target=invoke,
        name="jujutui-backend",
        daemon=True,
    )
    with _BACKEND_THREADS_LOCK:
        _BACKEND_THREADS.add(thread)
    try:
        thread.start()
    except BaseException:
        with _BACKEND_THREADS_LOCK:
            _BACKEND_THREADS.discard(thread)
        raise
    return await result


def finish_card_process(exit_code: int) -> int:
    """Bound shutdown even when a backend call is stuck in a daemon worker."""
    global _BACKEND_SHUTDOWN_GRACE, _BACKEND_TIMEOUT_EXIT_CODE, _BACKEND_EXIT_STATUS
    kill_owned_clipboards()
    with _BACKEND_THREADS_LOCK:
        grace = _BACKEND_SHUTDOWN_GRACE
        timeout_exit_code = _BACKEND_TIMEOUT_EXIT_CODE
    deadline = time.monotonic() + grace

    def complete(default_code: int) -> int:
        global _BACKEND_SHUTDOWN_GRACE, _BACKEND_TIMEOUT_EXIT_CODE, _BACKEND_EXIT_STATUS
        with _BACKEND_THREADS_LOCK:
            result = _BACKEND_EXIT_STATUS
            _BACKEND_SHUTDOWN_GRACE = 0.5
            _BACKEND_TIMEOUT_EXIT_CODE = 1
            _BACKEND_EXIT_STATUS = None
        return result if result is not None else default_code

    while True:
        with _BACKEND_THREADS_LOCK:
            threads = tuple(_BACKEND_THREADS)
        if not threads:
            return complete(exit_code if isinstance(exit_code, int) else 1)
        for thread in threads:
            thread.join(timeout=max(0.0, deadline - time.monotonic()))
        with _BACKEND_THREADS_LOCK:
            remaining = any(thread.is_alive() for thread in _BACKEND_THREADS)
        if not remaining:
            return complete(exit_code if isinstance(exit_code, int) else 1)
        if time.monotonic() >= deadline:
            try:
                os.write(2, b"Bitwarden card stopped a pending backend call.\n")
            except OSError:
                pass
            os._exit(timeout_exit_code if isinstance(timeout_exit_code, int) else 1)


def _card_css() -> str:
    palette = wallust_palette()
    background = palette.get("background", "#161821")
    foreground = palette.get("foreground", "#e6e8ef")
    accent = palette.get("accent", "#8aa2d3")
    secondary = palette.get("secondary", "#a8c88a")
    error = palette.get("error", "#e08a86")
    return f"""
    Screen {{
        background: {background};
        color: {foreground};
    }}
    #card {{
        width: 100%;
        height: 100%;
        margin: 0;
        padding: 1 2;
        align: center middle;
        background: {background};
        color: {foreground};
    }}
    #body {{
        width: 100%;
        height: auto;
    }}
    Header {{
        width: 100%;
        height: 2;
        margin-bottom: 1;
        border-bottom: tall {accent};
    }}
    .header-glyph {{
        width: 4;
        color: {accent};
        text-style: bold;
        content-align: center middle;
    }}
    .header-title {{
        width: 1fr;
        color: {accent};
        text-style: bold;
        content-align: left middle;
    }}
    #field-list {{
        width: 100%;
        height: auto;
        padding-top: 1;
    }}
    FieldRow {{
        width: 100%;
        height: auto;
        min-height: 1;
    }}
    .field-label {{
        width: 14;
        padding-right: 1;
        color: {secondary};
        text-style: dim;
        content-align: right middle;
    }}
    .field-value {{
        width: 1fr;
        color: {foreground};
        content-align: left middle;
    }}
    ButtonBar {{
        width: 100%;
        height: 3;
        align-horizontal: center;
        margin-top: 1;
    }}
    Button {{
        width: 1fr;
        min-width: 0;
        height: 3;
        margin: 0 1;
        border: round {secondary};
        background: {background};
        color: {foreground};
    }}
    Button:hover {{
        background: {accent};
        color: {background};
        text-style: bold;
    }}
    Button:focus {{
        border: round {foreground};
        background: {accent};
        color: {background};
        text-style: bold;
    }}
    Input {{
        width: 100%;
        height: 3;
        margin-top: 1;
        border: round {secondary};
        background: {background};
        color: {foreground};
    }}
    Input:focus {{
        border: round {accent};
    }}
    StatusLine {{
        width: 100%;
        height: 1;
        color: {secondary};
        content-align: center middle;
    }}
    StatusLine.error {{
        color: {error};
        text-style: bold;
    }}
    HintBar {{
        width: 100%;
        height: 1;
        color: {secondary};
        content-align: center middle;
    }}
    """


def create_card_app_class() -> tuple[type[Any], dict[str, Any]]:
    """Create the base App and widget namespace after debug env is removed."""
    clear_textual_debug_environment()
    # These widgets deliberately use their validated Wallust CSS palette.
    os.environ.pop("NO_COLOR", None)
    os.environ.pop("BW_SESSION", None)
    os.environ["BW_NOINTERACTION"] = "true"
    try:
        from textual.app import App, ComposeResult
        from textual.binding import Binding
        from textual.containers import Container, Horizontal
        from textual.widgets import Button, Input, Static
    except ImportError as exc:
        raise TextualUnavailable from exc

    class Header(Horizontal):
        """Accent title row shared by every card."""

        def __init__(self, glyph: str, title: str) -> None:
            super().__init__(classes="card-header")
            self._glyph = glyph
            self._title = title

        def compose(self) -> ComposeResult:
            yield Static(self._glyph, classes="header-glyph", markup=False)
            yield Static(self._title, classes="header-title", markup=False)

    class FieldRow(Horizontal):
        """Aligned, dim-label/bright-value pair."""

        def __init__(self, label: str, value: str) -> None:
            super().__init__(classes="field-row")
            self._label = label
            self._value = value

        def compose(self) -> ComposeResult:
            yield Static(self._label, classes="field-label", markup=False)
            yield Static(self._value, classes="field-value", markup=False)

    class ButtonBar(Horizontal):
        """Equal-width action row shared by every card."""

    class HintBar(Static):
        """Subtle one-line keyboard guide."""

        def __init__(self, text: str) -> None:
            super().__init__(text, markup=False)

    class StatusLine(Static):
        """Inline status message with a clipboard-expiry countdown."""

        def __init__(self) -> None:
            super().__init__("", markup=False)
            self._countdown_timer = None
            self._clear_timer = None
            self._countdown_label = ""
            self._seconds_remaining = 0

        def show_message(
            self, message: str, *, error: bool = False, timeout: float = 4.0
        ) -> None:
            self._stop_timers()
            self.set_class(error, "error")
            self.update(message)
            if timeout > 0:
                self._clear_timer = self.set_timer(timeout, self.clear_message)

        def show_countdown(self, label: str, seconds: int) -> None:
            self._stop_timers()
            self.set_class(False, "error")
            self._countdown_label = label
            self._seconds_remaining = seconds
            self._render_countdown()
            self._countdown_timer = self.set_interval(1.0, self._tick)

        def clear_message(self) -> None:
            self._stop_timers()
            self.set_class(False, "error")
            self.update("")

        def _render_countdown(self) -> None:
            self.update(
                f"{self._countdown_label} · clears in {self._seconds_remaining} s"
            )

        def _tick(self) -> None:
            self._seconds_remaining -= 1
            if self._seconds_remaining <= 0:
                if self._countdown_timer is not None:
                    self._countdown_timer.stop()
                    self._countdown_timer = None
                self.show_message("Clipboard expired", timeout=3.0)
                return
            self._render_countdown()

        def _stop_timers(self) -> None:
            if self._countdown_timer is not None:
                self._countdown_timer.stop()
                self._countdown_timer = None
            if self._clear_timer is not None:
                self._clear_timer.stop()
                self._clear_timer = None

        def on_unmount(self) -> None:
            self._stop_timers()

    class PasswordInput(Input):
        """Password field that cannot copy, cut, or retain clipboard text."""

        BINDINGS = [
            Binding("ctrl+x", "deny_clipboard", "", show=False),
            Binding("ctrl+c,super+c", "deny_clipboard", "", show=False),
        ]

        def action_deny_clipboard(self) -> None:
            return None

        def action_copy(self) -> None:
            return None

        def action_cut(self) -> None:
            return None

        def on_key(self, event: Any) -> None:
            # The focused Input consumes ordinary keys before App bindings.
            if event.key == "q":
                event.prevent_default()
                event.stop()
                self.app.action_close()

    class CardApp(App[None]):
        CSS = _card_css()
        BINDINGS = [
            Binding("escape", "close", "Close", show=False, priority=True),
            Binding("q", "close", "Close", show=False, priority=True),
            Binding("ctrl+q", "close", "Close", show=False, priority=True),
        ]
        TITLE = "Bitwarden"
        ENABLE_COMMAND_PALETTE = False
        ALLOW_SELECT = False
        watch_css = False

        def __init__(self, *, inactivity_timeout: int = 120) -> None:
            if (
                not isinstance(inactivity_timeout, int)
                or isinstance(inactivity_timeout, bool)
                or not 5 <= inactivity_timeout <= 120
            ):
                raise ValueError("invalid inactivity timeout")
            self._inactivity_timeout = inactivity_timeout
            self._inactivity_timer = None
            super().__init__()

        def compose(self) -> ComposeResult:
            with Container(id="card"):
                with Container(id="body"):
                    yield from self.compose_contents()

        def compose_contents(self) -> Iterable[Any]:
            return ()

        def on_mount(self) -> None:
            self._reset_inactivity()

        def on_key(self, _event: Any) -> None:
            self._reset_inactivity()

        def on_mouse_down(self, _event: Any) -> None:
            self._reset_inactivity()

        def on_mouse_up(self, _event: Any) -> None:
            self._reset_inactivity()

        def on_mouse_move(self, _event: Any) -> None:
            self._reset_inactivity()

        def _reset_inactivity(self) -> None:
            if self._inactivity_timer is not None:
                self._inactivity_timer.stop()
            self._inactivity_timer = self.set_timer(
                float(self._inactivity_timeout), self.action_close
            )

        def action_close(self) -> None:
            kill_owned_clipboards()
            self.exit()

        def copy_to_clipboard(self, _text: str) -> None:
            """Disable Textual's OSC 52 clipboard path for every card."""
            return None

        def on_unmount(self) -> None:
            kill_owned_clipboards()

        def _handle_exception(self, _error: Exception) -> None:
            """Replace Textual's traceback screen, which may include locals."""
            kill_owned_clipboards()
            try:
                self.exit(return_code=1, message="Unable to complete this action.")
            except Exception:
                # No traceback or exception text is safe to print from this path.
                os._exit(1)

        def on_button_pressed(self, _event: Any) -> None:
            self._reset_inactivity()

        def watch_worker(self, worker: Any, on_result: Any, on_failure: Any) -> None:
            """Deliver a thread worker's result back on Textual's event loop."""
            from textual.worker import WorkerCancelled, WorkerFailed

            async def wait_for_worker() -> None:
                try:
                    result = await worker.wait()
                except (WorkerCancelled, WorkerFailed):
                    on_failure()
                else:
                    on_result(result)

            self.run_worker(
                wait_for_worker,
                name="worker-result",
                group="worker-results",
                exit_on_error=False,
            )

        def run_backend_worker(
            self,
            function: Any,
            *args: Any,
            name: str,
            group: str,
            **kwargs: Any,
        ) -> Any:
            """Bridge one blocking call through an exit-safe daemon thread."""

            async def invoke() -> Any:
                return await _run_daemon_backend(function, *args, **kwargs)

            return self.run_worker(
                invoke,
                name=name,
                group=group,
                exit_on_error=False,
            )

    return CardApp, {
        "Binding": Binding,
        "Button": Button,
        "ButtonBar": ButtonBar,
        "Container": Container,
        "ComposeResult": ComposeResult,
        "FieldRow": FieldRow,
        "Header": Header,
        "HintBar": HintBar,
        "Horizontal": Horizontal,
        "Input": Input,
        "PasswordInput": PasswordInput,
        "StatusLine": StatusLine,
        "Static": Static,
    }


def run_card(app: Any) -> int:
    """Run one card with a fixed process-level exception handler and cleanup."""
    import threading

    def fixed_hook(_kind: type[BaseException], _error: BaseException, _tb: Any) -> None:
        try:
            os.write(2, b"Bitwarden card failed.\n")
        except OSError:
            pass

    sys.excepthook = fixed_hook
    if hasattr(threading, "excepthook"):
        threading.excepthook = lambda _args: fixed_hook(
            _args.exc_type, _args.exc_value, _args.exc_traceback
        )
    try:
        app.run()
        result = app.return_code
        return result if isinstance(result, int) else 0
    except BaseException:
        try:
            os.write(2, b"Bitwarden card failed.\n")
        except OSError:
            pass
        return 1
    finally:
        kill_owned_clipboards()

"""Run the real Bitwarden CLI with a minimal child-only environment.

The session token never appears in argv or in any exec'd environment: it is
written to an anonymous pipe and read by bootstrap.js, which sets
process.env.BW_SESSION inside node before loading the CLI.  So neither
/proc/PID/environ nor systemd-coredump's COREDUMP_ENVIRON can carry it.
BW_RESPONSE=true makes the CLI emit one JSON document, which is parsed here
and never forwarded to a terminal.

Only the canonical profile is used: children get HOME and no profile
variables, so the CLI always resolves ~/.config/Bitwarden CLI.
"""

import json
import os
import selectors
import subprocess
import time

REAL_BW = "/usr/bin/bw"
NODE = "/usr/bin/node"
BOOTSTRAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bootstrap.js")
DEFAULT_TIMEOUT = 30
MAX_OUTPUT = 64 * 1024 * 1024
POLL_SECONDS = 0.2

PROFILE_VARS = ("BITWARDENCLI_APPDATA_DIR", "XDG_CONFIG_HOME")


class BwFailure(Exception):
    """CLI could not be run or returned unparseable output (no data attached)."""


class Cancelled(BwFailure):
    """The caller's cancellation check fired; the child was killed, output discarded."""


def profile_dir(environ=None):
    environ = os.environ if environ is None else environ
    if environ.get("BITWARDENCLI_APPDATA_DIR"):
        return os.path.realpath(environ["BITWARDENCLI_APPDATA_DIR"])
    home = environ.get("HOME") or os.path.expanduser("~")
    base = environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    return os.path.realpath(os.path.join(base, "Bitwarden CLI"))


def canonical_profile(home):
    return profile_dir({"HOME": home})


def child_env(home=None, response=True, extra=None):
    """Minimal environment.  Never contains BW_SESSION or profile overrides."""
    env = {
        "PATH": "/usr/local/bin:/usr/bin:/bin",
        "HOME": home or os.path.expanduser("~"),
        "LANG": "C.UTF-8",
        "BW_NOINTERACTION": "true",
        "NO_COLOR": "1",
        "FORCE_COLOR": "0",
    }
    if response:
        env["BW_RESPONSE"] = "true"
    env.update(extra or {})
    return env


def _cli_js(bw):
    return os.path.realpath(bw or REAL_BW)


def argv_for(args, bw=None, token_fd=None):
    """argv for a CLI run; with token_fd the bootstrap delivers the session."""
    if token_fd is None:
        return [bw or REAL_BW, *args]
    return [NODE, BOOTSTRAP, _cli_js(bw), str(token_fd), *args]


def _kill(proc):
    try:
        proc.kill()
    except OSError:
        pass
    try:
        proc.wait(timeout=0.5)  # SIGKILL: normally reaped in milliseconds
    except subprocess.TimeoutExpired:
        pass


def run_raw(args, session=None, timeout=DEFAULT_TIMEOUT, pass_fds=(), bw=None, home=None,
            response=True, extra_env=None, cancelled=None, max_output=MAX_OUTPUT):
    """Supervised run.  Returns (returncode, stdout bytes, stderr bytes).

    The child is killed and BwFailure raised on timeout or oversized output;
    Cancelled is raised (output discarded) as soon as `cancelled()` is true.
    """
    token_r = token_w = None
    fds = tuple(pass_fds)
    try:
        if session is not None:
            token_r, token_w = os.pipe()
            os.set_inheritable(token_r, False)
            fds += (token_r,)
        try:
            proc = subprocess.Popen(
                argv_for(args, bw, token_r),
                env=child_env(home, response, extra_env),
                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                pass_fds=fds, close_fds=True, shell=False)
        except OSError:
            raise BwFailure("bitwarden cli could not start") from None
        if token_r is not None:
            os.close(token_r)
            token_r = None
            try:
                os.write(token_w, session.encode("ascii") + b"\n")  # < PIPE_BUF: one write
            except OSError:
                pass
            os.close(token_w)
            token_w = None
        return _collect(proc, timeout, cancelled, max_output)
    finally:
        for fd in (token_r, token_w):
            if fd is not None:
                os.close(fd)


def _collect(proc, timeout, cancelled, max_output):
    buffers = {proc.stdout: bytearray(), proc.stderr: bytearray()}
    selector = selectors.DefaultSelector()
    for stream in buffers:
        os.set_blocking(stream.fileno(), False)
        selector.register(stream, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    try:
        while selector.get_map():
            if cancelled is not None and cancelled():
                _kill(proc)
                raise Cancelled("cancelled")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                _kill(proc)
                raise BwFailure("bitwarden cli timed out")
            for key, _events in selector.select(min(POLL_SECONDS, remaining)):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                buffers[key.fileobj] += chunk
                if len(buffers[key.fileobj]) > max_output:
                    _kill(proc)
                    raise BwFailure("bitwarden cli output too large")
        while True:
            if cancelled is not None and cancelled():
                _kill(proc)
                raise Cancelled("cancelled")
            try:
                rc = proc.wait(timeout=min(POLL_SECONDS, max(deadline - time.monotonic(), 0.01)))
                break
            except subprocess.TimeoutExpired:
                if time.monotonic() >= deadline:
                    _kill(proc)
                    raise BwFailure("bitwarden cli timed out") from None
    except BaseException:
        if proc.poll() is None:
            _kill(proc)
        raise
    finally:
        selector.close()
        proc.stdout.close()
        proc.stderr.close()
    return rc, bytes(buffers[proc.stdout]), bytes(buffers[proc.stderr])


def run(args, session=None, timeout=DEFAULT_TIMEOUT, pass_fds=(), bw=None, home=None,
        cancelled=None):
    """Return (returncode, parsed JSON dict or None).  Raises BwFailure."""
    rc, out, _err = run_raw(args, session=session, timeout=timeout, pass_fds=pass_fds, bw=bw,
                            home=home, cancelled=cancelled)
    try:
        document = json.loads(out.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        document = None
    if not isinstance(document, dict):
        document = None
    return rc, document


def message_of(document):
    if not document:
        return ""
    message = document.get("message")
    return message.lower() if isinstance(message, str) else ""


def status(session=None, bw=None, home=None, timeout=20):
    """Return 'unlocked' | 'locked' | 'unauthenticated'.  Raises BwFailure."""
    rc, document = run(["status"], session=session, timeout=timeout, bw=bw, home=home)
    if rc != 0 or not document or document.get("success") is not True:
        raise BwFailure("status failed")
    data = document.get("data") or {}
    template = data.get("template") if isinstance(data.get("template"), dict) else data
    state = template.get("status") if isinstance(template, dict) else None
    if state not in ("unlocked", "locked", "unauthenticated"):
        raise BwFailure("status unparseable")
    return state


def lock(bw=None, home=None, timeout=20):
    """Real `bw lock` without a session.

    Returns 'locked', or 'unauthenticated' when nobody is logged in (nothing
    to lock), or None when the lock could not be confirmed.
    """
    try:
        rc, document = run(["lock"], timeout=timeout, bw=bw, home=home)
    except BwFailure:
        return None
    if rc == 0 and document and document.get("success") is True:
        return "locked"
    if "not logged in" in message_of(document):
        return "unauthenticated"
    return None

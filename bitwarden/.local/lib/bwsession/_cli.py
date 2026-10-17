"""Entry points for `bw-session` and the `bw` shim.  Fixed messages only."""

import argparse
import getpass
import json
import os
import sys
import time

import bwsession
from bwsession import _bw
from bwsession._core import MAX_PASSWORD_BYTES, Error, Expired, WrongPassword


def _say(message, stream=sys.stderr):
    print(message, file=stream, flush=True)


def _clock(epoch):
    return time.strftime("%H:%M", time.localtime(epoch)) if epoch else "?"


def _read_password_fd(fd):
    chunks = []
    total = 0
    while True:
        chunk = os.read(fd, 1024)
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_PASSWORD_BYTES + 2:
            raise Error("Password too long")
        chunks.append(chunk)
    os.close(fd)
    password = b"".join(chunks)
    if password.endswith(b"\n"):
        password = password[:-1]
    return password


def _desktop_context():
    """A prompt on the local desktop (not SSH): gate it on the desktop state."""
    return bool(os.environ.get("WAYLAND_DISPLAY")) and not os.environ.get("SSH_CONNECTION")


def _guarded(main):
    def wrapper():
        try:
            code = main()
        except KeyboardInterrupt:
            code = 130
        except SystemExit as exc:
            code = exc.code if isinstance(exc.code, int) else 2
        except BaseException:
            _say("bw-session: internal error")
            code = 2
        sys.stdout.flush()
        os._exit(code if isinstance(code, int) else 0)
    return wrapper


# -- bw-session ---------------------------------------------------------------
def _session_parser():
    parser = argparse.ArgumentParser(prog="bw-session", description="Bitwarden CLI session authority")
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status", help="print session state (never prompts)")
    status.add_argument("--json", action="store_true")
    unlock = sub.add_parser("unlock", help="unlock with the master password from a file descriptor")
    unlock.add_argument("--password-fd", type=int, metavar="N")
    lock = sub.add_parser("lock", help="lock now")
    lock.add_argument("--reason", choices=bwsession.PUBLIC_LOCK_REASONS, default="manual")
    pick = sub.add_parser("pick", help="choose an item with fuzzel; prints its ID")
    pick.add_argument("--with-generation", action="store_true",
                      help="print 'ID GENERATION' so the consumer can bind to that session")
    sub.add_parser("remind", help="passive, rate-limited 'locked' notification")
    sub.add_parser("guard", help="run the bw-session-guard service loop")
    sub.add_parser("_activation-check", help=argparse.SUPPRESS)
    expire = sub.add_parser("_expire", help=argparse.SUPPRESS)
    expire.add_argument("generation")
    return parser


@_guarded
def session_main():
    args = _session_parser().parse_args()
    if args.command == "status":
        result = bwsession.status()
        if args.json:
            print(json.dumps(result, separators=(",", ":")))
        elif result["state"] == "unlocked":
            print(f"unlocked until {_clock(result['deadline'])}")
        else:
            print(result["state"])
        return 0
    if args.command == "unlock":
        try:
            if args.password_fd is not None:
                if args.password_fd < 3:
                    raise Error("Use a dedicated descriptor (3 or higher)")
                password = _read_password_fd(args.password_fd)
            elif sys.stdin.isatty():
                password = getpass.getpass("Master password: ").encode("utf-8")
            else:
                raise Error("Use --password-fd N or an interactive terminal")
            bwsession.unlock(password, desktop=_desktop_context())
        except WrongPassword as exc:
            _say(f"bw-session: {exc}")
            return 1
        except Error as exc:
            _say(f"bw-session: {exc}")
            return 2
        finally:
            password = None
        return 0
    if args.command == "lock":
        try:
            bwsession.lock(args.reason)
        except Error as exc:
            _say(f"bw-session: {exc}")
            return 2
        return 0
    if args.command == "pick":
        try:
            chosen = bwsession.pick_bound()
        except Error as exc:
            _say(f"bw-session: {exc}")
            return 2
        if chosen is None:
            return 1
        print(f"{chosen[0]} {chosen[1]}" if args.with_generation else chosen[0])
        return 0
    if args.command == "remind":
        bwsession.remind()
        return 0
    if args.command == "guard":
        from bwsession._guard import Guard

        Guard(bwsession._default(internal=True)).run()
        return 1
    if args.command == "_activation-check":
        print(json.dumps(bwsession._default().activation_check(), separators=(",", ":")))
        return 0
    if args.command == "_expire":
        return 0 if bwsession._default(internal=True).expire(args.generation) else 2
    return 2


# -- bw shim ------------------------------------------------------------------
# Leading options the stock CLI accepts and the shim forwards.
GLOBAL_FLAGS = {"--pretty", "--response", "--quiet", "--nointeraction", "--cleanexit"}
PASSTHROUGH = {"", "help", "-h", "--help", "-v", "--version", "generate", "encode", "completion"}
# Session- or password-bearing options are refused wherever they appear.
REFUSED_OPTIONS = ("--session", "--raw", "--passwordenv", "--passwordfile", "--apikey")
GET_OBJECTS = {"item", "username", "password", "uri", "totp", "notes", "exposed", "folder",
               "collection", "organization", "template", "fingerprint"}
LIST_OBJECTS = {"items", "folders", "collections", "organizations", "org-collections",
                "org-members"}
LIST_VALUE_OPTIONS = {"--search", "--url", "--folderid", "--collectionid", "--organizationid"}
SESSION_TIMEOUTS = {"get": 60, "list": 120, "status": 30, "sync": 300}
OUTPUT_ENV = ("BW_PRETTY", "BW_QUIET", "BW_CLEANEXIT", "BW_RESPONSE")
UNSUPPORTED = ("bw: this command is not available through the managed shim; "
               "use /usr/bin/bw directly (unmanaged, outside the session authority)")


class Refused(Exception):
    pass


def _output_env():
    return {name: "true" for name in OUTPUT_ENV if os.environ.get(name) == "true"}


def _home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def _exec_bw(args):
    """Session-free passthrough: minimal environment, never a token."""
    env = _bw.child_env(_home(), response=False, extra=_output_env())
    os.execve(_bw.REAL_BW, ["bw", *args], env)


def parse_shim(args):
    """(flags, command, rest), or raises Refused with a fixed message."""
    for arg in args:
        if any(arg == opt or arg.startswith(opt + "=") for opt in REFUSED_OPTIONS):
            raise Refused("bw: --session, --raw and password options are refused here")
    flags = []
    index = 0
    while index < len(args) and args[index].startswith("-"):
        arg = args[index]
        if arg in ("-h", "--help", "-v", "--version"):
            return flags, arg, args[index + 1:]
        if arg not in GLOBAL_FLAGS:
            raise Refused("bw: unsupported option")
        flags.append(arg)
        index += 1
    command = args[index] if index < len(args) else ""
    rest = args[index + 1:]
    if command in PASSTHROUGH:
        return flags, command, rest
    if command == "unlock":
        if rest not in ([], ["--check"]):
            raise Refused("bw: unlock takes no password or options here "
                          "(it prompts in a terminal; --check reports the state)")
    elif command in ("lock", "logout", "status"):
        if rest:
            raise Refused(f"bw: {command} takes no arguments here")
    elif command == "login":
        raise Refused("bw: login is not managed here; run /usr/bin/bw login, then bw unlock")
    elif command == "serve":
        raise Refused("bw: serve is refused: it would hand the session to a long-lived server")
    elif command == "sync":
        if any(arg not in ("-f", "--force", "--last") for arg in rest):
            raise Refused("bw: unsupported sync option")
    elif command == "get":
        positional = [arg for arg in rest if not arg.startswith("-")]
        options = [arg for arg in rest if arg.startswith("-")]
        if options or not 1 <= len(positional) <= 2 or positional[0] not in GET_OBJECTS:
            raise Refused("bw: unsupported get form")
    elif command == "list":
        index, positional = 0, []
        while index < len(rest):
            arg = rest[index]
            if arg in LIST_VALUE_OPTIONS and index + 1 < len(rest):
                index += 2
                continue
            if arg == "--trash":
                index += 1
                continue
            if arg.startswith("-"):
                raise Refused("bw: unsupported list option")
            positional.append(arg)
            index += 1
        if len(positional) != 1 or positional[0] not in LIST_OBJECTS:
            raise Refused("bw: unsupported list form")
    else:
        raise Refused(UNSUPPORTED)
    return flags, command, rest


def _shim_unlock(args):
    if args == ["--check"]:
        if bwsession.status()["state"] == "unlocked":
            _say("Vault is unlocked.", sys.stdout)
            return 0
        _say("Vault is locked.")
        return 1
    if not (sys.stdin.isatty() and sys.stderr.isatty()):
        _say("bw: run `bw unlock` in an interactive terminal, or unlock from the bar")
        return 2
    try:
        password = getpass.getpass("Master password: ").encode("utf-8")
        bwsession.unlock(password, desktop=_desktop_context())
    except WrongPassword as exc:
        _say(f"bw: {exc}")
        return 1
    except Error as exc:
        _say(f"bw: {exc}")
        return 2
    finally:
        password = None
    result = bwsession.status()
    _say(f"Vault unlocked until {_clock(result.get('deadline'))}.", sys.stdout)
    return 0


def _locked_exit():
    if sys.stdin.isatty() and sys.stderr.isatty():
        _say("bw: vault is locked; run `bw unlock` or unlock from the bar")
    else:
        bwsession.remind()
        _say("bw: vault is locked; unlock from the bar or run `bw unlock` in a terminal")
    return 1


def _write_all(fd, data):
    view = memoryview(data)
    while view:
        view = view[os.write(fd, view):]


def run_supervised(authority, argv, timeout):
    """Run one session command; release its output only if the session survived.

    The child is killed as soon as the session is revoked or reaches its
    deadline; its output is discarded unless the same generation is still
    current afterwards.  stdout bytes are passed on unchanged.
    """
    epoch = authority.epoch()
    try:
        token, record = authority.session()
    except (Expired, Error):
        return None
    deadline = authority.effective_deadline(record) or 0
    try:
        rc, out, err = _bw.run_raw(
            argv, session=token, timeout=timeout, bw=authority.bw, home=authority.home,
            response=False, extra_env=_output_env(),
            cancelled=lambda: authority.revoked_since(epoch) or authority.clock.wall() >= deadline)
    except _bw.Cancelled:
        return None
    except _bw.BwFailure:
        _say("bw: Bitwarden CLI failed")
        return 2
    finally:
        token = None
    try:
        authority.session(record["generation"])
    except (Expired, Error):
        return None
    if authority.revoked_since(epoch):
        return None
    _write_all(1, out)
    _write_all(2, err)
    return rc


@_guarded
def shim_main():
    try:
        flags, command, rest = parse_shim(sys.argv[1:])
    except Refused as exc:
        _say(str(exc))
        return 2
    if command in PASSTHROUGH:
        _exec_bw(sys.argv[1:])
    authority = bwsession._default()
    if authority.profile_refused:
        _say(f"bw: {bwsession._core.PROFILE_REFUSED}; use /usr/bin/bw for other profiles")
        return 2
    if command == "unlock":
        return _shim_unlock(rest)
    if command in ("lock", "logout"):
        try:
            bwsession.lock("manual")
        except Error as exc:
            _say(f"bw: {exc}")
            return 2
        if command == "logout":
            _exec_bw([*flags, "logout"])
        _say("Your vault is locked.", sys.stdout)
        return 0
    code = run_supervised(authority, [*flags, command, *rest], SESSION_TIMEOUTS[command])
    if code is not None:
        return code
    if command == "status":
        _exec_bw([*flags, "status"])
    return _locked_exit()

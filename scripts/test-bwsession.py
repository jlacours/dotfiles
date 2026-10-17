#!/usr/bin/python3 -I
"""Tests for bitwarden/.local/lib/bwsession with a fake `bw`, memory keyring and fake clock.

Never touches the real vault.  The fake CLI is a node script, so session
calls go through the real bootstrap.js.  `--live` adds non-secret checks
against the real Secret Service (synthetic item), systemd user timers
(far-future timer, removed again), logind, a scratch never-logged-in profile
and a synthetic-token crash checked in the coredump journal.
"""

import contextlib
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import types
import unittest
from unittest import mock

from jeepney import MessageType

REPO = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
LIB = os.path.join(REPO, "bitwarden", ".local", "lib")
sys.path.insert(0, LIB)

import bwsession  # noqa: E402
from bwsession import _bw, _cli, _core, _desktop  # noqa: E402
from bwsession._config import Config, load_config  # noqa: E402
from bwsession._keyring import KeyringUnavailable, MemoryKeyring, SecretServiceKeyring  # noqa: E402
from bwsession._timer import FakeTimers  # noqa: E402

PASSWORD = "correct horse ⚡ battery"
ITEM_A = "11111111-1111-4111-8111-111111111111"
ITEM_B = "22222222-2222-4222-8222-222222222222"
ITEM_C = "33333333-3333-4333-8333-333333333333"
SYNTHETIC_SECRET = "SYNTHETIC-PASSWORD-MARKER-7f3a"


def write_fake_bw(directory):
    """A node fake of the CLI; state lives in a JSON file next to it."""
    state = os.path.join(directory, "state.json")
    log = os.path.join(directory, "calls.jsonl")
    script = os.path.join(directory, "bw.js")
    with open(state, "w") as handle:
        json.dump({"logged_in": True, "key": None, "password": PASSWORD, "delay": {},
                   "fail_lock": False, "garbage_unlock": False}, handle)
    source = textwrap.dedent(f'''\
        #!/usr/bin/node
        "use strict";
        const fs = require("fs");
        const STATE = {json.dumps(state)};
        const LOG = {json.dumps(log)};
        const ITEMS = [
          {{id: "{ITEM_B}", name: "zeta\\u202eevil\\nname", login: {{username: "bob\\u001b[31m",
            password: "{SYNTHETIC_SECRET}", uris: [{{uri: "https://b.example/\\u2066x"}}]}}}},
          {{id: "{ITEM_A}", name: "Alpha", login: {{username: "alice", password: "pw-a",
            uris: [{{uri: "https://a.example"}}]}}}},
          {{id: "{ITEM_C}", name: "Alpha", login: {{username: "alice", password: "pw-c"}}}},
          {{id: "not-a-uuid", name: "Broken"}},
        ];
        const args = process.argv.slice(2);
        const session = process.env.BW_SESSION;
        const environ = fs.readFileSync("/proc/self/environ", "latin1");
        fs.appendFileSync(LOG, JSON.stringify({{argv: args, env: Object.keys(process.env).sort(),
          has_session: session !== undefined, environ_session: environ.includes("BW_SESSION")}}) + "\\n");
        const load = () => JSON.parse(fs.readFileSync(STATE, "utf8"));
        let state = load();
        const cmd = args.find((a) => !a.startsWith("-")) || "";
        const rest = args.slice(args.indexOf(cmd) + 1);
        const delay = (state.delay || {{}})[cmd];
        if (delay) {{
          Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, delay * 1000);
          state = load();
        }}
        const json = process.env.BW_RESPONSE === "true";
        function out(doc, rc = 0) {{
          if (json || cmd === "status") {{
            process.stdout.write(JSON.stringify(doc) + "\\n");
          }} else if (doc.success) {{
            const data = doc.data || {{}};
            process.stdout.write(typeof data.data === "string" ? data.data : JSON.stringify(data));
          }} else {{
            process.stderr.write(doc.message + "\\n");
          }}
          process.exit(rc);
        }}
        const save = () => fs.writeFileSync(STATE, JSON.stringify(state));
        const unlocked = state.logged_in && state.key !== null && session === state.key;
        if (cmd === "status") {{
          const status = !state.logged_in ? "unauthenticated" : (unlocked ? "unlocked" : "locked");
          out({{success: true, data: {{object: "template", template: {{status}}}}}});
        }}
        if (cmd === "lock") {{
          if (state.fail_lock) out({{success: false, message: "Lock failed."}}, 1);
          if (!state.logged_in) out({{success: false, message: "You are not logged in."}}, 1);
          state.key = null; save();
          out({{success: true, data: {{object: "message", title: "Your vault is locked."}}}});
        }}
        if (cmd === "unlock") {{
          if (!state.logged_in) out({{success: false, message: "You are not logged in."}}, 1);
          const path = rest[rest.indexOf("--passwordfile") + 1];
          const line = fs.readFileSync(path, "utf8").split("\\n")[0];
          if (line !== state.password) out({{success: false, message: "Invalid master password."}}, 1);
          state.key = require("crypto").randomBytes(48).toString("base64url"); save();
          if (state.garbage_unlock) {{ process.stdout.write("garbage\\n"); process.exit(0); }}
          out({{success: true, data: {{object: "message", raw: state.key}}}});
        }}
        if (!unlocked) out({{success: false, message: "Vault is locked."}}, 1);
        if (cmd === "sync") out({{success: true, data: {{object: "message", title: "Syncing complete."}}}});
        if (cmd === "list" && rest[0] === "items") out({{success: true, data: {{object: "list", data: ITEMS}}}});
        if (cmd === "get") {{
          const item = ITEMS.find((i) => i.id === rest[1]);
          if (!item) out({{success: false, message: "Not found."}}, 1);
          if (rest[0] === "item") out({{success: true, data: Object.assign({{object: "item"}}, item)}});
          const value = (item.login || {{}})[rest[0]];
          if (value === undefined) out({{success: false, message: "Not found."}}, 1);
          out({{success: true, data: {{object: "string", data: value}}}});
        }}
        out({{success: false, message: "unsupported"}}, 1);
        ''')
    with open(script, "w") as handle:
        handle.write(source)
    os.chmod(script, 0o755)
    return script, state, log


def write_fake_fuzzel(directory):
    """fuzzel stand-in on PATH: records its input, then follows fuzzel.json."""
    bindir = os.path.join(directory, "bin")
    os.makedirs(bindir, exist_ok=True)
    script = os.path.join(bindir, "fuzzel")
    control = os.path.join(directory, "fuzzel.json")
    with open(script, "w") as handle:
        handle.write(textwrap.dedent(f'''\
            #!/usr/bin/python3 -I
            import json, os, sys, time
            data = sys.stdin.buffer.read()
            with open({control!r}) as handle:
                control = json.load(handle)
            with open({control!r} + ".seen", "w") as handle:
                json.dump({{"argv": sys.argv, "input": data.decode(), "env": sorted(os.environ)}}, handle)
            time.sleep(control.get("sleep", 0))
            sys.stdout.write(control.get("stdout", ""))
            sys.exit(control.get("rc", 0))
            '''))
    os.chmod(script, 0o755)
    return bindir, control


class FakeClock:
    def __init__(self):
        self.now = 1_800_000_000.0
        self.boot = 5_000.0
        self.sleep_total = 0.0
        self.boot_identity = "boot-a"

    def wall(self):
        return self.now

    def boottime(self):
        return self.boot

    def slept(self):
        return self.sleep_total

    def boot_id(self):
        return self.boot_identity

    def advance(self, seconds):
        self.now += seconds
        self.boot += seconds

    def suspend(self, seconds):
        self.advance(seconds)
        self.sleep_total += seconds


class HookTimers(FakeTimers):
    def __init__(self):
        super().__init__()
        self.on_arm = None

    def arm(self, generation, deadline):
        if self.on_arm is not None:
            hook, self.on_arm = self.on_arm, None
            hook()
        return super().arm(generation, deadline)


@contextlib.contextmanager
def held_lock(runtime):
    """Hold the transition lock from another process (contention)."""
    path = os.path.join(os.path.dirname(runtime), "bwsession.lock")
    child = subprocess.Popen(
        [sys.executable, "-I", "-c", textwrap.dedent(f'''
            import fcntl, os, sys
            fd = os.open({path!r}, os.O_RDWR | os.O_CREAT, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX)
            sys.stdout.write("held\\n"); sys.stdout.flush()
            sys.stdin.read()
            ''')], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        assert child.stdout.readline() == b"held\n"
        yield
    finally:
        child.stdin.close()
        child.wait(timeout=10)
        child.stdout.close()


@contextlib.contextmanager
def captured_fds():
    """Capture what is written to fds 1 and 2."""
    saved = os.dup(1), os.dup(2)
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        os.dup2(out.fileno(), 1)
        os.dup2(err.fileno(), 2)
        result = {}
        try:
            yield result
        finally:
            os.dup2(saved[0], 1)
            os.dup2(saved[1], 2)
            for fd in saved:
                os.close(fd)
            out.seek(0)
            err.seek(0)
            result["out"], result["err"] = out.read(), err.read()


class Later:
    """Run `action` after `delay` seconds in a thread; join and report it."""

    def __init__(self, delay, action):
        self.done = threading.Event()

        def run():
            time.sleep(delay)
            action()
            self.done.set()

        self.thread = threading.Thread(target=run)
        self.thread.start()

    def join(self):
        self.thread.join()
        return self.done.is_set()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.bw, self.state_path, self.log_path = write_fake_bw(self.dir)
        self.runtime = os.path.join(self.dir, "run", "bwsession")
        os.makedirs(self.runtime, mode=0o700)
        self.keyring = MemoryKeyring()
        self.timers = HookTimers()
        self.clock = FakeClock()
        self.config = Config()
        self.desktop_ok = True
        self.auth = self.authority()
        # Hostile caller environment must not reach the child.
        self.env_patch = mock.patch.dict(os.environ, {
            "NODE_OPTIONS": "--require=/evil.js", "BITWARDENCLI_DEBUG": "true",
            "BW_SESSION": "hostile-session-value-0000", "XDG_CONFIG_HOME": "/elsewhere"})
        self.env_patch.start()

    def authority(self, **overrides):
        options = dict(
            keyring=self.keyring, timers=self.timers, bw=self.bw, config=self.config,
            clock=self.clock, runtime_dir=self.runtime, migrate_legacy=True,
            environ={"USER": "tester", "HOME": self.dir},
            desktop_gate=lambda _full: self.desktop_ok)
        options.update(overrides)
        return _core.Authority(**options)

    def tearDown(self):
        self.env_patch.stop()
        self.tmp.cleanup()

    def bw_state(self):
        with open(self.state_path) as handle:
            return json.load(handle)

    def set_bw(self, **values):
        state = self.bw_state()
        state.update(values)
        with open(self.state_path, "w") as handle:
            json.dump(state, handle)

    def calls(self):
        if not os.path.exists(self.log_path):
            return []
        with open(self.log_path) as handle:
            return [json.loads(line) for line in handle]

    def unlock(self):
        self.auth.unlock(PASSWORD.encode("utf-8"))
        return self.auth.status()

    def assert_clean(self):
        self.assertEqual(self.keyring.items, {})
        self.assertIsNone(self.bw_state()["key"])
        self.assertFalse(os.path.exists(os.path.join(self.runtime, "txn")))
        self.assertFalse(os.path.exists(os.path.join(self.runtime, "pending")))

    def assert_no_token_leak(self):
        token = self.bw_state()["key"]
        for call in self.calls():
            argv = " ".join(call["argv"])
            self.assertNotIn("BW_SESSION", argv)
            self.assertNotIn(PASSWORD, argv)
            if token:
                self.assertNotIn(token, argv)
            self.assertFalse(call["environ_session"], "token in the exec-time environment")
            for name in ("NODE_OPTIONS", "BITWARDENCLI_DEBUG", "XDG_CONFIG_HOME",
                         "BITWARDENCLI_APPDATA_DIR"):
                self.assertNotIn(name, call["env"])
            self.assertIn("BW_NOINTERACTION", call["env"])


class UnlockTests(Base):
    def test_unlock_success_arms_timer_and_reports_status(self):
        result = self.unlock()
        self.assertEqual(result["state"], "unlocked")
        self.assertEqual(set(result), {"schema", "state", "deadline", "generation", "message"})
        self.assertRegex(result["generation"], r"^[0-9a-f]{8}$")
        self.assertEqual(result["deadline"], int(self.clock.now) + 8 * 3600)
        self.assertEqual(self.timers.armed, {result["generation"]: result["deadline"]})
        self.assertEqual(len(self.keyring.items), 1)
        attrs, secret = next(iter(self.keyring.items.values()))
        self.assertEqual(attrs["generation"], result["generation"])
        self.assertNotIn("token", attrs)
        self.assertEqual(json.loads(secret)["token"], self.bw_state()["key"])
        self.assertFalse(os.path.exists(os.path.join(self.runtime, "txn")))
        self.assert_no_token_leak()

    def test_session_calls_get_token_only_through_bootstrap(self):
        result = self.unlock()
        self.auth.secret(ITEM_A, "password", result["generation"])
        session_calls = [c for c in self.calls() if c["has_session"]]
        self.assertTrue(session_calls)
        self.assertEqual({c["argv"][0] for c in session_calls}, {"get"})
        self.assert_no_token_leak()

    def test_password_goes_through_dev_fd_pipe(self):
        self.unlock()
        unlock_call = [c for c in self.calls() if c["argv"][:1] == ["unlock"]][0]
        self.assertRegex(unlock_call["argv"][-1], r"^/dev/fd/\d+$")
        self.assertFalse(unlock_call["has_session"])

    def test_wrong_password(self):
        with self.assertRaises(bwsession.WrongPassword):
            self.auth.unlock(b"nope")
        self.assert_clean()
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_no_token_leak()

    def test_rejects_newlines_and_empty(self):
        with self.assertRaises(bwsession.Error):
            self.auth.unlock(b"a\nb")
        with self.assertRaises(bwsession.Error):
            self.auth.unlock(b"a\rb")
        with self.assertRaises(bwsession.WrongPassword):
            self.auth.unlock(b"")
        self.assertEqual(self.calls(), [])

    def test_not_logged_in(self):
        self.set_bw(logged_in=False)
        with self.assertRaises(bwsession.Error) as ctx:
            self.auth.unlock(PASSWORD.encode())
        self.assertNotIsInstance(ctx.exception, bwsession.WrongPassword)
        self.assertEqual(self.auth.status()["state"], "unauthenticated")

    def test_keyring_locked_refuses_before_bw(self):
        self.keyring.locked = True
        with self.assertRaises(bwsession.Error):
            self.unlock()
        self.assertEqual(self.calls(), [])

    def test_reunlock_replaces_generation(self):
        first = self.unlock()
        second = self.unlock()
        self.assertNotEqual(first["generation"], second["generation"])
        self.assertEqual(len(self.keyring.items), 1)
        self.assertNotIn(first["generation"], self.timers.armed)


class TransactionTests(Base):
    """Fault injection at every unlock/lock mutation boundary (R2, R3)."""

    def test_no_secret_before_commit(self):
        seen = {}

        def reader():
            for name, call in (("session", lambda: self.auth.session()),
                               ("secret", lambda: self.auth.secret(ITEM_B, "password", "00000000"))):
                try:
                    call()
                    seen[name] = "released"
                except bwsession.Expired:
                    seen[name] = "denied"
            seen["status"] = self.auth.status()["state"]

        self.timers.on_arm = reader
        result = self.unlock()
        self.assertEqual(seen, {"session": "denied", "secret": "denied", "status": "locked"})
        self.assertEqual(result["state"], "unlocked")

    def test_interrupt_at_each_boundary_cleans_up(self):
        boundaries = {
            "before-store": lambda: setattr(self.keyring, "fail_create", True),
            "at-arm": lambda: setattr(self.timers, "on_arm", self._raise_interrupt),
            "arm-fails": lambda: setattr(self.timers, "fail", True),
        }
        for name, inject in boundaries.items():
            with self.subTest(boundary=name):
                inject()
                with self.assertRaises((bwsession.Error, KeyboardInterrupt)):
                    self.unlock()
                self.keyring.fail_create = False
                self.timers.fail = False
                self.assert_clean()
                self.assertEqual(self.timers.armed, {})
                self.assertEqual(self.auth.check_expiry(), True)
                self.assertEqual(self.auth.status()["state"], "locked")

    @staticmethod
    def _raise_interrupt():
        raise KeyboardInterrupt

    def test_cli_failure_after_profile_mutation_cleans_up(self):
        real_run = _bw.run

        def run_then_fail(args, **kwargs):
            outcome = real_run(args, **kwargs)
            if args[:1] == ["unlock"]:
                raise _bw.BwFailure("timed out after the CLI saved its key")
            return outcome

        with mock.patch.object(_bw, "run", run_then_fail):
            with self.assertRaises(bwsession.Error):
                self.unlock()
        self.assert_clean()

    def test_unexpected_cli_output_cleans_up(self):
        self.set_bw(garbage_unlock=True)
        with self.assertRaises(bwsession.Error) as ctx:
            self.unlock()
        self.assertNotIsInstance(ctx.exception, bwsession.WrongPassword)
        self.assert_clean()

    def test_dead_unlock_is_recovered(self):
        # What a SIGKILLed unlock leaves: txn marker, a record, no timer, unlocked profile.
        self.unlock()
        self.timers.armed.clear()
        self.auth._write_json("txn", {"op": "unlock", "epoch": self.auth.epoch()})
        with self.assertRaises(bwsession.Expired):
            self.auth.session()
        self.assert_clean()
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_killed_unlock_process_is_recovered(self):
        self.set_bw(delay={"unlock": 1.0})
        child = subprocess.Popen([sys.executable, "-I", "-c", textwrap.dedent(f'''
            import sys
            sys.path.insert(0, {LIB!r})
            from bwsession import _core
            from bwsession._keyring import MemoryKeyring
            from bwsession._timer import FakeTimers
            auth = _core.Authority(keyring=MemoryKeyring(), timers=FakeTimers(), bw={self.bw!r},
                                   runtime_dir={self.runtime!r}, migrate_legacy=False,
                                   environ={{"USER": "tester", "HOME": {self.dir!r}}},
                                   desktop_gate=lambda full: True)
            auth.unlock({PASSWORD.encode()!r})
            ''')])
        deadline = time.monotonic() + 10
        while not os.path.exists(os.path.join(self.runtime, "txn")):
            self.assertLess(time.monotonic(), deadline)
            time.sleep(0.05)
        os.kill(child.pid, signal.SIGKILL)
        child.wait()
        time.sleep(1.5)  # the orphaned CLI finishes and saves its key
        self.assertTrue(self.bw_state()["key"])
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_lock_during_unlock_is_not_a_false_success(self):
        self.set_bw(delay={"unlock": 1.5})
        outcome = {}

        def lock_while_unlocking():
            time.sleep(0.5)
            outcome["revoke"] = self.auth.revoke("suspend", timeout=0.2)
            # Success is only ever reported for a state that is really clean.
            outcome["clean"] = not self.keyring.items and self.bw_state()["key"] is None
            outcome["status"] = self.auth.status()["state"]

        thread = threading.Thread(target=lock_while_unlocking)
        thread.start()
        with self.assertRaises(bwsession.Error):
            self.unlock()
        thread.join()
        if outcome["revoke"]:
            self.assertTrue(outcome["clean"])
        self.assertNotEqual(outcome["status"], "unlocked")
        self.assert_clean()
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_lock_in_commit_window_aborts_commit(self):
        outcome = {}

        def revoke_now():
            outcome["revoke"] = self.auth.revoke("manual", timeout=0.1)

        self.timers.on_arm = revoke_now
        with self.assertRaises(bwsession.Error):
            self.unlock()
        self.assertFalse(outcome["revoke"])
        self.assert_clean()

    def test_cancel_epoch_aborts_unlock(self):
        self.timers.on_arm = self.auth.cancel_unlocks
        with self.assertRaises(bwsession.Error):
            self.unlock()
        self.assert_clean()

    def test_revoke_with_stuck_holder_keeps_denying_then_retries(self):
        result = self.unlock()
        with held_lock(self.runtime):
            self.assertFalse(self.auth.revoke("manual", timeout=0.3))
            self.assertIsNone(self.bw_state()["key"])  # profile lock still ran
            self.assertEqual(len(self.keyring.items), 1)  # records left to the holder
            with self.assertRaises(bwsession.Expired):
                self.auth.secret(ITEM_B, "password", result["generation"])
            self.assertEqual(self.auth.status()["state"], "error")
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_stale_reader_does_not_revoke_new_generation(self):
        self.unlock()
        self.auth._remove("verified")
        real_status = _bw.status
        replaced = {}

        def status_racing_with_unlock(session=None, bw=None, home=None, timeout=20):
            if session is not None and "done" not in replaced:
                replaced["done"] = True
                self.auth.unlock(PASSWORD.encode())  # concurrent lock + unlock -> new generation
                replaced["generation"] = next(iter(self.keyring.items.values()))[0]["generation"]
            return real_status(session=session, bw=bw, home=home, timeout=timeout)

        with mock.patch.object(_bw, "status", status_racing_with_unlock):
            first = self.auth.status()
        self.assertEqual(first["state"], "unlocked")
        self.assertEqual(first["generation"], replaced["generation"])


class CancellationOrderTests(Base):
    """N1: an unlock never commits after a cancellation or lock that began
    after its ticket, wherever that lands; a cancel after commit is handled
    by revoking the returned generation."""

    def _inject_at_lock_entry(self, action):
        real = _core.Authority.serialized
        fired = []

        def serialized(auth, timeout):
            if not fired:
                fired.append(1)
                action()
            return real(auth, timeout)
        return mock.patch.object(_core.Authority, "serialized", serialized)

    def unlock_calls(self):
        return [c for c in self.calls() if c["argv"][:1] == ["unlock"]]

    def test_cancel_while_waiting_for_the_lock(self):
        with self._inject_at_lock_entry(self.auth.cancel_unlocks):
            with self.assertRaises(bwsession.Error):
                self.unlock()
        self.assertEqual(self.unlock_calls(), [])
        self.assert_clean()
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_completed_lock_while_waiting_is_not_overtaken(self):
        outcome = {}
        with self._inject_at_lock_entry(lambda: outcome.setdefault("revoke", self.auth.revoke("manual"))):
            with self.assertRaises(bwsession.Error):
                self.unlock()
        self.assertTrue(outcome["revoke"])
        self.assertEqual(self.unlock_calls(), [])
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_cancel_after_the_last_slow_check(self):
        real = _core.Authority._remember

        def remember(auth, key, state):
            real(auth, key, state)
            if key.startswith("gen:"):
                auth.cancel_unlocks()

        with mock.patch.object(_core.Authority, "_remember", remember):
            with self.assertRaises(bwsession.Error):
                self.unlock()
        self.assert_clean()
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_cancel_after_commit_then_abandoned_attempt_revokes_its_generation(self):
        real = _core.Authority._remove

        def remove(auth, name):
            real(auth, name)
            if name == "txn":
                auth.cancel_unlocks()

        with mock.patch.object(_core.Authority, "_remove", remove):
            generation = self.auth.unlock(PASSWORD.encode())
        self.assertEqual(self.auth.status()["generation"], generation)  # committed first
        self.assertTrue(self.auth.lock_generation(generation))
        self.assert_clean()

    def test_ticket_cancelled_before_worker_start(self):
        ticket = self.auth.cancel_token()
        self.auth.cancel_unlocks()
        with self.assertRaises(bwsession.Error):
            self.auth.unlock(PASSWORD.encode(), ticket=ticket)
        self.assertEqual(self.calls(), [])

    def test_ticket_survives_own_replace_cleanup(self):
        self.unlock()
        ticket = self.auth.cancel_token()
        generation = self.auth.unlock(PASSWORD.encode(), ticket=ticket)
        self.assertEqual(self.auth.status()["generation"], generation)

    def test_lock_generation_leaves_a_newer_session(self):
        old = self.auth.unlock(PASSWORD.encode())
        new = self.auth.unlock(PASSWORD.encode())
        self.assertTrue(self.auth.lock_generation(old))
        self.assertEqual(self.auth.status()["generation"], new)
        with self.assertRaises(bwsession.Error):
            self.auth.lock_generation("not-a-generation")


class StatusCoherenceTests(Base):
    """N4: status never reports a generation that was revoked during the call."""

    def test_revoke_during_status_cli_check(self):
        self.unlock()
        self.auth._remove("verified")
        real = _bw.status

        def status_then_revoke(session=None, bw=None, home=None, timeout=20):
            result = real(session=session, bw=bw, home=home, timeout=timeout)
            self.assertTrue(self.auth.revoke("manual"))
            return "unlocked"  # the stale answer the CLI gave before the lock

        with mock.patch.object(_bw, "status", status_then_revoke):
            self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_replaced_during_status_reports_the_new_generation(self):
        self.unlock()
        self.auth._remove("verified")
        real = _bw.status
        seen = {}

        def status_then_replace(session=None, bw=None, home=None, timeout=20):
            result = real(session=session, bw=bw, home=home, timeout=timeout)
            if "new" not in seen:
                seen["new"] = self.auth.unlock(PASSWORD.encode())
            return result

        with mock.patch.object(_bw, "status", status_then_replace):
            result = self.auth.status()
        self.assertEqual((result["state"], result["generation"]), ("unlocked", seen["new"]))

    def test_session_read_discarded_when_revoked_meanwhile(self):
        result = self.unlock()
        real = self.keyring.get_secret

        def get_then_revoke(item):
            secret = real(item)
            self.auth.revoke("manual")
            return secret

        with mock.patch.object(self.keyring, "get_secret", get_then_revoke):
            with self.assertRaises(bwsession.Expired):
                self.auth.session(result["generation"])

    def test_whole_status_call_is_bounded(self):
        self.unlock()
        self.auth._remove("verified")
        self.set_bw(delay={"status": 30})
        with mock.patch.object(_core, "STATUS_BUDGET", 1.0):
            started = time.monotonic()
            self.assertEqual(self.auth.status()["state"], "error")
        self.assertLess(time.monotonic() - started, 2.0)


class SlowKeyring(MemoryKeyring):
    """Memory keyring whose search blocks like a slow D-Bus call, within its deadline."""

    def __init__(self):
        super().__init__()
        self.search_delay = 0.0

    def search(self, attributes):
        if self.search_delay:
            wait = self.remaining(self.search_delay)
            time.sleep(wait)
            if wait < self.search_delay:
                raise KeyringUnavailable("timed out")
        return super().search(attributes)


class BudgetTests(Base):
    """N7: suspend ends sessions without a usable grace period, and a budgeted
    revocation caps every blocking cleanup step."""

    def setUp(self):
        super().setUp()
        self.keyring = SlowKeyring()
        self.auth = self.authority(keyring=self.keyring)

    def test_one_second_suspend_ends_session(self):
        result = self.unlock()
        self.clock.suspend(1.0)
        with self.assertRaises(bwsession.Expired):
            self.auth.secret(ITEM_B, "password", result["generation"])
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_tenth_of_a_second_suspend_ends_session(self):
        self.unlock()
        self.clock.suspend(0.1)
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_budget_caps_keyring_steps(self):
        result = self.unlock()
        self.keyring.search_delay = 0.6
        started = time.monotonic()
        self.assertFalse(self.auth.revoke("suspend", budget=0.2))
        self.assertLess(time.monotonic() - started, 0.45)
        self.assertTrue(os.path.exists(os.path.join(self.runtime, "pending")))
        self.keyring.search_delay = 0.0
        with self.assertRaises(bwsession.Expired):
            self.auth.secret(ITEM_B, "password", result["generation"])
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_budget_caps_lock_wait_and_cli(self):
        self.unlock()
        self.set_bw(delay={"lock": 5})
        with held_lock(self.runtime):
            started = time.monotonic()
            self.assertFalse(self.auth.revoke("suspend", budget=0.8))
            self.assertLess(time.monotonic() - started, 0.8 + 0.6)
        self.set_bw(delay={})
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()


class FakeSecretService:
    """Synthetic Secret Service transport with Jeepney's blocking semantics.

    A request sent while another is in flight gets no reply of its own
    (the other caller consumed it), which surfaces as TimeoutError.
    """

    COLLECTION = "/org/freedesktop/secrets/collection/login"

    def __init__(self):
        self.items = {}
        self.counter = 0
        self.inflight = 0
        self.max_inflight = 0
        self.crossed = 0
        self.guard = threading.Lock()

    def close(self):
        pass

    @staticmethod
    def reply(*body, error=None):
        if error:
            return types.SimpleNamespace(header=types.SimpleNamespace(
                message_type=MessageType.error, fields={4: error}), body=())
        return types.SimpleNamespace(header=types.SimpleNamespace(
            message_type=MessageType.method_return, fields={}), body=body)

    def send_and_get_reply(self, msg, timeout=None):
        with self.guard:
            self.inflight += 1
            self.max_inflight = max(self.max_inflight, self.inflight)
            crossed = self.inflight > 1
        try:
            time.sleep(0.001)
            if crossed:
                with self.guard:
                    self.crossed += 1
                raise TimeoutError("reply consumed by another caller")
            return self.handle(msg)
        finally:
            with self.guard:
                self.inflight -= 1

    def handle(self, msg):
        fields = msg.header.fields
        path, member, body = fields.get(1), fields.get(3), msg.body
        if member == "ReadAlias":
            return self.reply(self.COLLECTION)
        if member == "Get":
            _iface, name = body
            if name == "Locked":
                return self.reply(("b", False))
            if name == "Attributes":
                return self.reply(("a{ss}", self.items[path][0]))
        if member == "OpenSession":
            if body[0] != "plain":
                return self.reply(error="org.freedesktop.DBus.Error.NotSupported")
            return self.reply(("s", ""), "/org/freedesktop/secrets/session/1")
        if member == "SearchItems":
            (attributes,) = body
            found = [p for p, (attrs, _s) in self.items.items()
                     if all(attrs.get(k) == v for k, v in attributes.items())]
            return self.reply(found, [])
        if member == "GetSecret":
            return self.reply((body[0], b"", self.items[path][1], "application/json"))
        if member == "CreateItem":
            properties, formatted, _replace = body
            attrs = properties["org.freedesktop.Secret.Item.Attributes"][1]
            self.counter += 1
            item = f"{self.COLLECTION}/{self.counter}"
            self.items[item] = (dict(attrs), bytes(formatted[2]))
            return self.reply(item, "/")
        if member == "Delete":
            self.items.pop(path, None)
            return self.reply("/")
        return self.reply(error="org.freedesktop.DBus.Error.UnknownMethod")


class ConcurrencyTests(Base):
    """N8: concurrent status/secret callers share one blocking connection safely."""

    def setUp(self):
        super().setUp()
        self.transport = FakeSecretService()
        self.ring = SecretServiceKeyring()
        self.ring._conn = self.transport
        self.auth = self.authority(keyring=self.ring)

    def hammer(self, ring_calls=None, seconds=1.5):
        errors = []
        stop = time.monotonic() + seconds

        def loop(call):
            while time.monotonic() < stop:
                try:
                    call()
                except Exception as exc:  # noqa: BLE001 - collected for the assertion
                    errors.append(type(exc).__name__)

        threads = [threading.Thread(target=loop, args=(call,)) for call in ring_calls]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        return errors

    def test_concurrent_status_and_secret_over_one_connection(self):
        generation = self.auth.unlock(PASSWORD.encode())
        results = {"status": set(), "secret": set()}

        def status():
            results["status"].add(self.auth.status()["state"])

        def secret():
            results["secret"].add(self.auth.secret(ITEM_A, "password", generation))

        errors = self.hammer([status, status, secret, secret])
        self.assertEqual(errors, [])
        self.assertEqual(results, {"status": {"unlocked"}, "secret": {b"pw-a"}})
        self.assertEqual(self.transport.max_inflight, 1)
        self.assertEqual(self.transport.crossed, 0)

    def test_transport_double_detects_unserialized_use(self):
        class NoLock:
            def acquire(self, timeout=None):
                return True

            def release(self):
                pass

        self.ring._op_lock = NoLock()
        attributes = {"application": "x"}
        errors = self.hammer([lambda: self.ring.search(attributes)] * 4, seconds=0.5)
        self.assertGreater(self.transport.crossed, 0)
        self.assertIn("KeyringUnavailable", errors)

    def test_lock_wait_is_bounded(self):
        self.ring.LOCK_WAIT = 0.2
        acquired = threading.Event()
        release = threading.Event()

        def holder():
            with self.ring._op_lock:
                acquired.set()
                release.wait(5)

        thread = threading.Thread(target=holder)
        thread.start()
        acquired.wait(5)
        started = time.monotonic()
        with self.assertRaises(KeyringUnavailable):
            self.ring.collection_locked()
        self.assertLess(time.monotonic() - started, 1.0)
        release.set()
        thread.join()


class ExpiryTests(Base):
    def test_absolute_deadline(self):
        self.unlock()
        self.clock.advance(8 * 3600 - 5)
        self.assertEqual(self.auth.status()["state"], "unlocked")
        self.clock.advance(10)
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()
        self.assertEqual(self.timers.armed, {})

    def test_wall_clock_rollback_does_not_extend(self):
        self.unlock()
        self.clock.boot += 8 * 3600
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_large_backward_step_denies(self):
        self.unlock()
        self.clock.now -= 3600
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_reboot_invalidates(self):
        self.unlock()
        self.clock.boot_identity = "boot-b"
        self.clock.boot = 10.0
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_shorter_config_shrinks_existing_session(self):
        self.unlock()
        self.auth._config = Config(ttl_hours=1)
        self.assertEqual(self.auth.status()["deadline"], int(self.clock.now) + 3600)
        self.clock.advance(3601)
        self.assertEqual(self.auth.status()["state"], "locked")

    def test_polls_do_not_renew(self):
        result = self.unlock()
        for _ in range(5):
            self.clock.advance(600)
            self.assertEqual(self.auth.status()["deadline"], result["deadline"])

    def test_expire_callback_checks_generation_and_deadline(self):
        current = self.unlock()
        self.assertTrue(self.auth.expire("deadbeef"))  # stale generation: no-op
        self.assertTrue(self.auth.expire(current["generation"]))  # not yet due: kept
        self.assertEqual(self.auth.status()["state"], "unlocked")
        self.clock.advance(8 * 3600)
        self.assertTrue(self.auth.expire(current["generation"]))
        self.assert_clean()

    def test_expire_without_lock_changes_nothing(self):
        current = self.unlock()
        self.clock.advance(8 * 3600)
        with held_lock(self.runtime), mock.patch.object(_core.Authority, "serialized",
                                                         self._quick_serialized()):
            self.assertFalse(self.auth.expire(current["generation"]))
            self.assertEqual(len(self.keyring.items), 1)
        with self.assertRaises(bwsession.Expired):
            self.auth.session()
        self.assertTrue(self.auth.check_expiry())
        self.assert_clean()

    @staticmethod
    def _quick_serialized():
        real = _core.Authority.serialized

        def serialized(self, timeout):
            return real(self, min(timeout, 0.2))
        return serialized

    def test_reconcile_rearms_or_expires(self):
        current = self.unlock()
        self.timers.armed.clear()
        self.assertTrue(self.auth.reconcile())
        self.assertIn(current["generation"], self.timers.armed)
        self.clock.boot_identity = "boot-b"
        self.auth.reconcile()
        self.assert_clean()

    def test_reconcile_without_record_verifies_profile_lock(self):
        self.set_bw(key="unmanaged-session-key-0123456789")
        self.assertTrue(self.auth.reconcile())
        self.assertIsNone(self.bw_state()["key"])

    def test_reconcile_with_locked_keyring_locks_bw_and_leaves_pending(self):
        self.unlock()
        self.keyring.locked = True
        self.assertFalse(self.auth.reconcile())
        self.assertIsNone(self.bw_state()["key"])
        self.assertEqual(self.auth.status()["state"], "keyring-locked")
        self.keyring.locked = False
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_check_expiry_tick(self):
        self.unlock()
        self.clock.advance(9 * 3600)
        self.auth.check_expiry()
        self.assert_clean()

    def test_check_expiry_rearms_missing_timer(self):
        current = self.unlock()
        self.timers.armed.clear()
        self.assertTrue(self.auth.check_expiry())
        self.assertIn(current["generation"], self.timers.armed)
        self.timers.armed.clear()
        self.timers.fail = True
        self.assertTrue(self.auth.check_expiry())  # cannot re-arm: revoked, cleanly
        self.assert_clean()

    def test_suspend_ends_session_without_guard(self):
        result = self.unlock()
        self.clock.suspend(30)
        with self.assertRaises(bwsession.Expired):
            self.auth.secret(ITEM_B, "password", result["generation"])
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_suspend_kept_when_policy_allows(self):
        self.auth._config = Config(lock_on_suspend=False)
        self.unlock()
        self.clock.suspend(30)
        self.assertEqual(self.auth.status()["state"], "unlocked")


class ImplicitCleanupTests(Base):
    """R8: a failed implicit revocation is never reported as `locked`."""

    def _store(self, payload):
        self.keyring.create("x", dict(self.auth._attributes(), generation="abcdef12"), payload)

    def test_expired_record_with_failing_bw_lock(self):
        self.unlock()
        self.clock.advance(9 * 3600)
        self.set_bw(fail_lock=True)
        self.assertEqual(self.auth.status()["state"], "error")
        self.assertEqual(self.auth.status()["state"], "error")
        self.set_bw(fail_lock=False)
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_duplicate_record_with_failing_delete(self):
        self.unlock()
        self._store(b"{}")
        self.keyring.fail_delete = True
        self.assertEqual(self.auth.status()["state"], "error")
        self.keyring.fail_delete = False
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_legacy_with_failing_bw_lock(self):
        self.keyring.create("legacy", {"application": "bitwarden-cli-session", "account": "tester"},
                            b"legacy-token")
        self.set_bw(fail_lock=True)
        self.assertEqual(self.auth.status()["state"], "error")

    def test_missing_record_verifies_profile_lock(self):
        self.set_bw(key="unmanaged-session-key-0123456789")
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assertIsNone(self.bw_state()["key"])
        self.set_bw(fail_lock=True, key=None)
        self.auth._remove("verified")
        self.assertEqual(self.auth.status()["state"], "error")

    def test_malformed_record_denied(self):
        self.unlock()
        for path in list(self.keyring.items):
            attrs, _ = self.keyring.items[path]
            self.keyring.items[path] = (attrs, b"{not json")
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_missing_fields_denied(self):
        self.unlock()
        path = next(iter(self.keyring.items))
        attrs, secret = self.keyring.items[path]
        record = json.loads(secret)
        del record["slept"]
        self.keyring.items[path] = (attrs, json.dumps(record).encode())
        with self.assertRaises(bwsession.Expired):
            self.auth.session()
        self.assertIsNone(self.bw_state()["key"])

    def test_legacy_item_migrated(self):
        self.keyring.create("legacy", {"application": "bitwarden-cli-session", "account": "tester"},
                            b"legacy-token")
        self.set_bw(key="legacy-token-value-1234567890")
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_external_lock_detected(self):
        self.unlock()
        self.set_bw(key=None)
        self.auth._remove("verified")
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assertEqual(self.keyring.items, {})


class FailureTests(Base):
    def test_keyring_unavailable_status_error(self):
        self.keyring.unavailable = True
        self.assertEqual(self.auth.status()["state"], "error")

    def test_lock_without_keyring_still_locks_bw(self):
        self.unlock()
        self.keyring.unavailable = True
        self.assertFalse(self.auth.revoke("manual"))
        self.assertIsNone(self.bw_state()["key"])
        self.assertEqual(self.auth._read_json("pending"), {"reason": "manual", "bw_locked": True})
        self.keyring.unavailable = False
        with self.assertRaises(bwsession.Expired):
            self.auth.session()
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()

    def test_public_lock_raises_on_incomplete(self):
        with mock.patch.object(bwsession, "_authority", self.auth):
            self.unlock()
            self.keyring.fail_delete = True
            with self.assertRaises(bwsession.Error):
                bwsession.lock("manual")
            with self.assertRaises(bwsession.Error):
                bwsession.lock("bogus")

    def test_serialized_timeout(self):
        with self.auth.serialized(1) as first:
            self.assertTrue(first)
            with self.auth.serialized(0.2) as second:
                self.assertFalse(second)  # per open file description: even this process waits

    def test_runtime_files_private(self):
        self.unlock()
        self.auth.revoke("manual")
        for name in os.listdir(self.runtime):
            mode = os.stat(os.path.join(self.runtime, name)).st_mode & 0o777
            self.assertEqual(mode, 0o600, name)
            with open(os.path.join(self.runtime, name)) as handle:
                content = handle.read()
            self.assertNotIn(PASSWORD, content)

    def test_slow_cli_is_bounded(self):
        self.unlock()
        self.set_bw(delay={"lock": 30})
        started = time.monotonic()
        self.assertFalse(self.auth.revoke("suspend", budget=1.5))
        self.assertLess(time.monotonic() - started, 4)
        with self.assertRaises(bwsession.Expired):
            self.auth.session()
        self.set_bw(delay={})
        self.assertEqual(self.auth.status()["state"], "locked")
        self.assert_clean()


class ProfileTests(Base):
    """R7: only the canonical profile is managed."""

    def test_alternate_profiles_refused(self):
        for environ in ({"USER": "tester", "HOME": self.dir, "BITWARDENCLI_APPDATA_DIR": "/x"},
                        {"USER": "tester", "HOME": self.dir, "XDG_CONFIG_HOME": "/x"}):
            auth = self.authority(environ=environ)
            self.assertEqual(auth.status()["state"], "error")
            for call in (lambda: auth.unlock(PASSWORD.encode()), auth.session,
                         lambda: auth.revoke("manual")):
                with self.assertRaises(bwsession.Error):
                    call()
        self.assertEqual(self.calls(), [])

    def test_explicit_default_profile_accepted(self):
        auth = self.authority(environ={"USER": "tester", "HOME": self.dir,
                                       "XDG_CONFIG_HOME": os.path.join(self.dir, ".config")})
        self.assertFalse(auth.profile_refused)

    def test_internal_entry_points_ignore_caller_profile(self):
        auth = self.authority(environ={"USER": "tester", "HOME": self.dir, "XDG_CONFIG_HOME": "/x"},
                              enforce_profile=False)
        auth.unlock(PASSWORD.encode())
        self.assertEqual(auth.status()["state"], "unlocked")
        self.assert_no_token_leak()

    def test_legacy_migration_only_for_real_home(self):
        auth = _core.Authority(keyring=self.keyring, runtime_dir=self.runtime,
                               environ={"USER": "tester", "HOME": self.dir})
        self.assertFalse(auth.migrate_legacy)


class DesktopGateTests(Base):
    """R10 (W half): desktop prompts never commit behind a locked desktop."""

    def test_desktop_unlock_refused_when_locked(self):
        self.desktop_ok = False
        with self.assertRaises(bwsession.Error):
            self.auth.unlock(PASSWORD.encode(), desktop=True)
        self.assertEqual(self.calls(), [])

    def test_desktop_locking_during_unlock_cancels(self):
        self.set_bw(delay={"unlock": 1.0})

        def lock_desktop():
            time.sleep(0.3)
            self.desktop_ok = False

        thread = threading.Thread(target=lock_desktop)
        thread.start()
        with self.assertRaises(bwsession.Error):
            self.auth.unlock(PASSWORD.encode(), desktop=True)
        thread.join()
        self.assert_clean()

    def test_terminal_unlock_ignores_desktop(self):
        self.desktop_ok = False
        self.auth.unlock(PASSWORD.encode(), desktop=False)
        self.assertEqual(self.auth.status()["state"], "unlocked")

    def test_desktop_unlocked_requires_wayland_and_no_hyprlock(self):
        with mock.patch.dict(os.environ, {"WAYLAND_DISPLAY": ""}):
            self.assertFalse(_desktop.desktop_unlocked())
        with mock.patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-1"}), \
                mock.patch.object(_desktop, "hyprlock_running", return_value=True):
            self.assertFalse(_desktop.desktop_unlocked())
        with mock.patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-1"}), \
                mock.patch.object(_desktop, "hyprlock_running", return_value=False), \
                mock.patch.object(_desktop, "_logind_display_active", side_effect=OSError):
            self.assertFalse(_desktop.desktop_unlocked())


class ConsumerTests(Base):
    def test_meta_sanitized(self):
        self.unlock()
        meta = self.auth.meta(ITEM_B)
        self.assertEqual(meta, {"name": "zetaevil name", "username": "bob[31m",
                                "uris": ["https://b.example/x"]})
        self.assertNotIn(SYNTHETIC_SECRET, json.dumps(meta))

    def test_meta_rejects_bad_id(self):
        self.unlock()
        with self.assertRaises(bwsession.Error):
            self.auth.meta("../../etc")

    def test_secret_requires_current_generation(self):
        result = self.unlock()
        with self.assertRaises(bwsession.Expired):
            self.auth.secret(ITEM_B, "password", "00000000")
        self.assertEqual(self.auth.secret(ITEM_B, "password", result["generation"]),
                         SYNTHETIC_SECRET.encode())
        self.assertEqual(self.auth.secret(ITEM_A, "username", result["generation"]), b"alice")
        with self.assertRaises(bwsession.Error):
            self.auth.secret(ITEM_A, "totp", result["generation"])
        self.assert_no_token_leak()

    def test_secret_discarded_when_generation_changes_mid_call(self):
        result = self.unlock()
        real_run = _bw.run

        def run_then_relock(*args, **kwargs):
            outcome = real_run(*args, **kwargs)
            self.keyring.items.clear()
            return outcome

        with mock.patch.object(_bw, "run", run_then_relock):
            with self.assertRaises(bwsession.Expired):
                self.auth.secret(ITEM_B, "password", result["generation"])

    def test_secret_request_killed_on_lock(self):
        result = self.unlock()
        self.set_bw(delay={"get": 5})
        later = Later(0.5, lambda: self.auth.revoke("manual"))
        started = time.monotonic()
        with self.assertRaises(bwsession.Expired):
            self.auth.secret(ITEM_B, "password", result["generation"])
        self.assertLess(time.monotonic() - started, 3)
        self.assertTrue(later.join())

    def test_secret_after_expiry(self):
        result = self.unlock()
        self.clock.advance(8 * 3600)
        with self.assertRaises(bwsession.Expired):
            self.auth.secret(ITEM_B, "password", result["generation"])

    def test_list_entries_with_duplicates(self):
        self.unlock()
        entries = self.auth.list_entries()
        self.assertEqual(entries, [("Alpha — alice", ITEM_A), ("Alpha — alice", ITEM_C),
                                   ("zetaevil name — bob[31m", ITEM_B)])


class PickerTests(Base):
    """R9: the picker is bound to one generation and closed on lock/expiry."""

    def setUp(self):
        super().setUp()
        bindir, self.fuzzel_control = write_fake_fuzzel(self.dir)
        os.environ["PATH"] = bindir + os.pathsep + os.environ.get("PATH", "/usr/bin")

    def fuzzel(self, **control):
        with open(self.fuzzel_control, "w") as handle:
            json.dump(control, handle)

    def seen(self):
        with open(self.fuzzel_control + ".seen") as handle:
            return json.load(handle)

    def test_index_mapping_and_duplicates(self):
        result = self.unlock()
        for index, expected in ((0, ITEM_A), (1, ITEM_C), (2, ITEM_B)):
            self.fuzzel(stdout=f"{index}\n")
            self.assertEqual(_desktop.pick(self.auth), (expected, result["generation"]))
        seen = self.seen()
        self.assertIn("--index", seen["argv"])
        self.assertIn("--cache=/dev/null", seen["argv"])
        self.assertNotIn(ITEM_A, seen["input"])
        self.assertNotIn(SYNTHETIC_SECRET, seen["input"])
        self.assertEqual(seen["input"].count("\n"), 3)
        self.assertFalse(any(k.startswith("BW_") for k in seen["env"]))

    def test_cancel_and_bad_output(self):
        self.unlock()
        for control in ({"stdout": "", "rc": 1}, {"stdout": "-1\n"}):
            self.fuzzel(**control)
            self.assertIsNone(_desktop.pick(self.auth))
        for bad in ("3\n", "1; rm\n", "+1\n"):
            self.fuzzel(stdout=bad)
            with self.assertRaises(bwsession.Error):
                _desktop.pick(self.auth)

    def _pick_while(self, action):
        self.fuzzel(stdout="0\n", sleep=3)
        later = Later(0.5, action)
        started = time.monotonic()
        result = _desktop.pick(self.auth)
        elapsed = time.monotonic() - started
        self.assertTrue(later.join())
        self.assertGreater(elapsed, 0.5)  # closed because of the action, not by itself
        self.assertLess(elapsed, 2.5)
        return result

    def test_lock_while_open(self):
        self.unlock()
        self.assertIsNone(self._pick_while(lambda: self.auth.revoke("manual")))

    def test_expiry_while_open(self):
        self.unlock()
        self.assertIsNone(self._pick_while(lambda: self.clock.advance(8 * 3600)))

    def test_reunlock_before_selection(self):
        self.unlock()
        self.assertIsNone(self._pick_while(lambda: self.auth.unlock(PASSWORD.encode())))

    def test_pick_locked(self):
        with self.assertRaises(bwsession.Expired):
            _desktop.pick(self.auth)


class ShimTests(Base):
    """R4/R5: grammar, allowlist and supervised session commands."""

    def test_grammar_accepts(self):
        cases = {
            ("get", "password", ITEM_A): ([], "get"),
            ("--pretty", "get", "item", ITEM_A): (["--pretty"], "get"),
            ("list", "items", "--search", "mail"): ([], "list"),
            ("sync", "-f"): ([], "sync"),
            ("unlock",): ([], "unlock"),
            ("unlock", "--check"): ([], "unlock"),
            ("lock",): ([], "lock"),
            ("status",): ([], "status"),
            ("--version",): ([], "--version"),
            ("generate", "-ulns"): ([], "generate"),
        }
        for argv, (flags, command) in cases.items():
            with self.subTest(argv=argv):
                parsed = _cli.parse_shim(list(argv))
                self.assertEqual(parsed[:2], (flags, command))

    def test_grammar_refuses(self):
        for argv in (["--raw", "unlock"], ["unlock", "--raw"], ["unlock", "hunter2"],
                     ["--session", "x", "list", "items"], ["--session=x", "status"],
                     ["get", "password", ITEM_A, "--session=x"], ["login"], ["login", "--raw"],
                     ["--quiet", "login"], ["serve"], ["--pretty", "serve", "--hostname", "all"],
                     ["export"], ["config", "server", "x"], ["get", "attachment", "a", "--output", "/tmp"],
                     ["list", "items", "--bogus"], ["unlock", "--passwordenv", "X"],
                     ["--frobnicate", "get"], ["logout", "now"], ["get", "secrets", ITEM_A]):
            with self.subTest(argv=argv):
                with self.assertRaises(_cli.Refused):
                    _cli.parse_shim(argv)

    def test_refusals_end_to_end(self):
        for argv, fragment in ((["login"], b"/usr/bin/bw login, then bw unlock"),
                               (["serve"], b"serve is refused"),
                               (["--raw", "unlock"], b"refused")):
            with self.subTest(argv=argv):
                proc = subprocess.run(
                    [sys.executable, "-I", "-c",
                     f"import sys; sys.path.insert(0, {LIB!r}); sys.argv = {['bw', *argv]!r}; "
                     "from bwsession._cli import shim_main; shim_main()"],
                    capture_output=True, timeout=30, check=False)
                self.assertEqual(proc.returncode, 2)
                self.assertIn(fragment, proc.stderr)
                self.assertEqual(proc.stdout, b"")

    def test_vdirsyncer_get_password_exact_bytes(self):
        self.unlock()
        with captured_fds() as io:
            code = _cli.run_supervised(self.auth, ["get", "password", ITEM_B], 30)
        self.assertEqual(code, 0)
        self.assertEqual(io["out"], SYNTHETIC_SECRET.encode())
        self.assertEqual(io["err"], b"")
        self.assert_no_token_leak()

    def test_no_output_escapes_after_lock(self):
        self.unlock()
        self.set_bw(delay={"get": 3})
        later = Later(0.5, lambda: self.auth.revoke("manual"))
        with captured_fds() as io:
            code = _cli.run_supervised(self.auth, ["get", "password", ITEM_B], 30)
        self.assertTrue(later.join())
        self.assertIsNone(code)
        self.assertEqual(io["out"], b"")
        self.assertNotIn(SYNTHETIC_SECRET.encode(), io["err"])

    def test_output_discarded_if_generation_changed(self):
        self.unlock()
        real = _bw.run_raw
        replaced = []

        def run_then_replace(*args, **kwargs):
            outcome = real(*args, **kwargs)
            if not replaced:
                replaced.append(1)
                self.auth.unlock(PASSWORD.encode())  # nested CLI calls go to `real`
            return outcome

        with mock.patch.object(_bw, "run_raw", run_then_replace), captured_fds() as io:
            code = _cli.run_supervised(self.auth, ["get", "password", ITEM_B], 30)
        self.assertIsNone(code)
        self.assertEqual(io["out"], b"")

    def test_locked_returns_none(self):
        with captured_fds() as io:
            self.assertIsNone(_cli.run_supervised(self.auth, ["get", "password", ITEM_B], 30))
        self.assertEqual(io["out"], b"")


class RemindTests(Base):
    def test_rate_limit_and_suppression(self):
        sent = []
        with mock.patch.object(_desktop, "_spawn_notification", lambda: sent.append(1)), \
                mock.patch.object(_desktop, "suppressed", return_value=False):
            self.assertEqual(_desktop.remind(self.auth), "sent")
            self.assertEqual(_desktop.remind(self.auth), "rate-limited")
            self.auth.revoke("manual")  # new lock period
            self.assertEqual(_desktop.remind(self.auth), "rate-limited")  # min interval
            self.clock.advance(_desktop.REMIND_MIN_INTERVAL + 1)
            self.assertEqual(_desktop.remind(self.auth), "sent")
            self.unlock()
            self.assertEqual(_desktop.remind(self.auth), "not-locked")
        with mock.patch.object(_desktop, "_spawn_notification", lambda: sent.append(1)), \
                mock.patch.object(_desktop, "suppressed", return_value=True):
            self.auth.revoke("manual")
            self.clock.advance(_desktop.REMIND_MIN_INTERVAL + 1)
            self.assertEqual(_desktop.remind(self.auth), "suppressed")
        self.assertEqual(len(sent), 2)

    def test_suppressed_without_active_desktop(self):
        with mock.patch.object(_desktop, "desktop_unlocked", return_value=False):
            self.assertTrue(_desktop.suppressed())

    def test_disabled(self):
        self.auth._config = Config(remind=False)
        self.assertEqual(_desktop.remind(self.auth), "disabled")


class ConfigTests(unittest.TestCase):
    def test_parsing_is_bounded_data(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as handle:
            handle.write("TTL_HOURS=$(touch /tmp/pwned)\nLOCK_ON_SUSPEND=no\n"
                         "LOCK_ON_SCREENLOCK=yes\nIDLE_LOCK_MIN=99999\n")
        try:
            config = load_config(handle.name)
        finally:
            os.unlink(handle.name)
        self.assertEqual(config, Config(ttl_hours=8, lock_on_suspend=False,
                                        lock_on_screenlock=True, idle_lock_min=0))
        with tempfile.NamedTemporaryFile("w", delete=False) as handle:
            handle.write("TTL_HOURS=25\n")
        try:
            self.assertEqual(load_config(handle.name).ttl_hours, 8)
        finally:
            os.unlink(handle.name)
        self.assertEqual(load_config("/nonexistent").ttl_hours, 8)

    def test_repo_default_config_matches_defaults(self):
        path = os.path.join(REPO, "bitwarden", ".config", "bw-session.conf")
        self.assertEqual(load_config(path), Config())


class StaticTests(unittest.TestCase):
    LIB = os.path.join(LIB, "bwsession")

    def read(self, name):
        with open(os.path.join(self.LIB, name), encoding="utf-8") as handle:
            return handle.read()

    def test_keyring_never_unlocks_or_prompts(self):
        source = self.read("_keyring.py")
        self.assertIsNone(re.search(r'["\']Unlock["\']', source))
        self.assertIsNone(re.search(r'["\']Prompt["\'],', source))
        self.assertNotIn("exec_prompt", source)
        self.assertNotIn("import secretstorage\n", source)

    def test_no_session_in_argv_env_or_passwordenv(self):
        for name in os.listdir(self.LIB):
            if name.endswith(".py"):
                source = self.read(name)
                self.assertNotIn('["--session"', source, name)
                self.assertNotIn("passwordenv", source.replace('"--passwordenv"', ""), name)
                self.assertNotIn("shell=True", source, name)
                self.assertNotIn('env["BW_SESSION"]', source, name)

    def test_hardening_applied_on_import(self):
        import ctypes
        import resource

        self.assertEqual(resource.getrlimit(resource.RLIMIT_CORE), (0, 0))
        libc = ctypes.CDLL(None)
        self.assertEqual(libc.prctl(3, 0, 0, 0, 0), 0)  # PR_GET_DUMPABLE

    def test_bootstrap_rejects_non_pipe_fd_and_bad_token(self):
        bootstrap = os.path.join(self.LIB, "bootstrap.js")
        env = {"PATH": "/usr/bin", "HOME": "/nonexistent"}
        proc = subprocess.run([_bw.NODE, bootstrap, "/nonexistent.js", "9"], env=env,
                              capture_output=True, timeout=30, check=False)
        self.assertEqual(proc.returncode, 70)
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b"short\n")
        os.close(write_fd)
        proc = subprocess.run([_bw.NODE, bootstrap, "/nonexistent.js", str(read_fd)], env=env,
                              pass_fds=(read_fd,), capture_output=True, timeout=30, check=False)
        os.close(read_fd)
        self.assertEqual(proc.returncode, 70)

    def test_sanitize(self):
        self.assertEqual(_core.sanitize("a‮b⁦c\nd\x00e f"), "abc de f")
        self.assertEqual(_core.sanitize(None), "")
        self.assertEqual(len(_core.sanitize("x" * 500)), 120)


class CliTests(unittest.TestCase):
    def test_password_fd_reader(self):
        read_fd, write_fd = os.pipe()
        os.write(write_fd, b"secret line\n")
        os.close(write_fd)
        self.assertEqual(_cli._read_password_fd(read_fd), b"secret line")

    def test_parser_contract(self):
        parser = _cli._session_parser()
        self.assertTrue(parser.parse_args(["status", "--json"]).json)
        self.assertEqual(parser.parse_args(["unlock", "--password-fd", "5"]).password_fd, 5)
        self.assertEqual(parser.parse_args(["lock", "--reason", "suspend"]).reason, "suspend")
        self.assertTrue(parser.parse_args(["pick", "--with-generation"]).with_generation)
        with open(os.devnull, "w") as devnull, contextlib.redirect_stderr(devnull):
            with self.assertRaises(SystemExit):
                parser.parse_args(["lock", "--reason", "whatever"])

    def test_cli_subprocess_error_is_sanitized(self):
        script = os.path.join(REPO, "bitwarden", ".local", "bin", "bw-session")
        proc = subprocess.run([script, "unlock", "--password-fd", "1"], capture_output=True,
                              timeout=30, check=False)
        self.assertEqual(proc.returncode, 2)
        self.assertNotIn(b"Traceback", proc.stderr)


class GuardTests(Base):
    def guard(self, config=None, authority=None):
        from bwsession._guard import Guard

        if config is not None:
            self.auth._config = config
        guard = Guard(authority or self.auth)
        guard.take_inhibitor = mock.Mock()
        guard.delay_seconds = 2.0
        return guard

    @staticmethod
    def msg(member, body, path="/org/freedesktop/login1"):
        header = mock.Mock()
        header.fields = {3: member, 1: path}
        return mock.Mock(header=header, body=body)

    def handle(self, guard, msg):
        with open(os.devnull, "w") as devnull, contextlib.redirect_stderr(devnull):
            guard.handle(msg)

    def test_sleep_locks_and_releases_inhibitor(self):
        self.unlock()
        guard = self.guard()
        inhibitor = mock.Mock()
        guard.inhibitor = inhibitor
        self.handle(guard, self.msg("PrepareForSleep", (True,)))
        inhibitor.close.assert_called_once()
        self.assertIsNone(guard.inhibitor)
        self.assert_clean()
        self.handle(guard, self.msg("PrepareForSleep", (False,)))
        guard.take_inhibitor.assert_called_once()

    def test_sleep_with_contended_lock_denies_at_once_within_budget(self):
        result = self.unlock()
        guard = self.guard()
        guard.inhibitor = mock.Mock()
        with held_lock(self.runtime):
            started = time.monotonic()
            self.handle(guard, self.msg("PrepareForSleep", (True,)))
            self.assertLess(time.monotonic() - started, guard.delay_seconds + 0.5)
            self.assertIsNone(guard.inhibitor)
            self.assertIsNone(self.bw_state()["key"])
            with self.assertRaises(bwsession.Expired):
                self.auth.secret(ITEM_B, "password", result["generation"])
        self.handle(guard, self.msg("PrepareForSleep", (False,)))
        self.assert_clean()

    def test_sleep_with_hung_cli_stays_in_budget(self):
        self.unlock()
        self.set_bw(delay={"lock": 30})
        guard = self.guard()
        guard.inhibitor = mock.Mock()
        started = time.monotonic()
        self.handle(guard, self.msg("PrepareForSleep", (True,)))
        self.assertLess(time.monotonic() - started, guard.delay_seconds + 0.5)
        with self.assertRaises(bwsession.Expired):
            self.auth.session()
        self.set_bw(delay={})
        self.handle(guard, self.msg("PrepareForSleep", (False,)))
        self.assert_clean()

    def test_inhibitor_denied_still_locks(self):
        from bwsession._guard import Guard

        self.unlock()
        guard = Guard(self.auth)
        guard._call = mock.Mock(side_effect=TimeoutError)
        with open(os.devnull, "w") as devnull, contextlib.redirect_stderr(devnull):
            guard.take_inhibitor()
            self.assertIsNone(guard.inhibitor)
            self.assertEqual(guard.read_delay_budget(), 5.0)
            guard.handle(self.msg("PrepareForSleep", (True,)))
        self.assert_clean()

    def test_delay_budget_read_from_logind(self):
        from bwsession._guard import Guard

        guard = Guard(self.auth)
        guard._call = mock.Mock(return_value=mock.Mock(body=(("t", 3_000_000),)))
        self.assertEqual(guard.read_delay_budget(), 3.0)
        self.assertAlmostEqual(guard.sleep_budget(), 2.25)

    def test_sleep_ignored_when_disabled_but_cancels_prompts(self):
        self.unlock()
        guard = self.guard(Config(lock_on_suspend=False))
        ticket = self.auth.cancel_token()
        self.handle(guard, self.msg("PrepareForSleep", (True,)))
        self.assertNotEqual(self.auth.cancel_token(), ticket)
        self.assertEqual(self.auth.status()["state"], "unlocked")

    def test_screenlock_cancels_prompts_and_locks_only_when_enabled(self):
        self.unlock()
        guard = self.guard()
        guard._session_uid = mock.Mock(return_value=os.getuid())
        ticket = self.auth.cancel_token()
        self.handle(guard, self.msg("Lock", (), "/org/freedesktop/login1/session/_31"))
        self.assertNotEqual(self.auth.cancel_token(), ticket)
        self.assertEqual(self.auth.status()["state"], "unlocked")
        guard._session_uid = mock.Mock(return_value=os.getuid() + 1)
        ticket = self.auth.cancel_token()
        self.handle(guard, self.msg("Lock", (), "/org/freedesktop/login1/session/_32"))
        self.assertEqual(self.auth.cancel_token(), ticket)
        guard = self.guard(Config(lock_on_screenlock=True))
        guard._session_uid = mock.Mock(return_value=os.getuid())
        self.handle(guard, self.msg("Lock", (), "/org/freedesktop/login1/session/_31"))
        self.assert_clean()


class LiveTests(unittest.TestCase):
    """Non-secret checks against real services; enabled with --live."""

    def test_secret_service_roundtrip_synthetic(self):
        from bwsession._keyring import SecretServiceKeyring

        keyring = SecretServiceKeyring()
        attrs = {"application": "bwsession-selftest", "account": "selftest", "generation": "0badc0de"}
        try:
            if keyring.collection_locked():
                self.skipTest("login keyring locked")
            for item in keyring.search(attrs):
                keyring.delete(item)
            keyring.create("bwsession self-test (synthetic)", attrs, b'{"synthetic":true}')
            items = keyring.search(attrs)
            self.assertEqual(len(items), 1)
            self.assertEqual(keyring.item_generation(items[0]), "0badc0de")
            self.assertEqual(keyring.get_secret(items[0]), b'{"synthetic":true}')
        finally:
            for item in keyring.search(attrs):
                keyring.delete(item)
            self.assertEqual(keyring.search(attrs), [])
            keyring.close()

    def test_systemd_timer_arm_disarm(self):
        from bwsession._timer import SystemdTimers

        timers = SystemdTimers()
        generation = "0badc0de"
        script = os.path.join(REPO, "bitwarden", ".local", "bin", "bw-session")
        try:
            with mock.patch("bwsession._timer.bw_session_path", return_value=script):
                self.assertTrue(timers.arm(generation, 4_000_000_000))
            self.assertTrue(timers.is_armed(generation))
        finally:
            timers.disarm(generation)
        self.assertFalse(timers.is_armed(generation))

    def test_logind_delay_inhibitor_and_budget(self):
        from jeepney import Properties, new_method_call
        from jeepney.io.blocking import open_dbus_connection
        from bwsession._guard import MANAGER

        with open_dbus_connection(bus="SYSTEM", enable_fds=True) as conn:
            reply = conn.send_and_get_reply(new_method_call(
                MANAGER, "Inhibit", "ssss", ("sleep", "bwsession-selftest", "self-test", "delay")),
                timeout=5)
            self.assertTrue(reply.body, "Inhibit refused")
            reply.body[0].close()
            (_sig, usec), = conn.send_and_get_reply(
                Properties(MANAGER).get("InhibitDelayMaxUSec"), timeout=5).body
            self.assertGreater(usec, 0)

    def test_desktop_gate_live(self):
        self.assertIsInstance(_desktop.desktop_unlocked(), bool)

    def test_scratch_profile_status_and_lock(self):
        with tempfile.TemporaryDirectory() as home:
            self.assertEqual(_bw.status(home=home), "unauthenticated")
            self.assertEqual(_bw.lock(home=home), "unauthenticated")

    def test_status_cli_refuses_alternate_profile(self):
        script = os.path.join(REPO, "bitwarden", ".local", "bin", "bw-session")
        with tempfile.TemporaryDirectory() as profile:
            env = dict(os.environ, BITWARDENCLI_APPDATA_DIR=profile)
            proc = subprocess.run([script, "status", "--json"], capture_output=True, env=env,
                                  timeout=60, check=False)
        self.assertEqual(proc.returncode, 0)
        result = json.loads(proc.stdout)
        self.assertEqual(set(result), {"schema", "state", "deadline", "generation", "message"})
        self.assertEqual(result["state"], "error")

    def test_crash_metadata_synthetic_token(self):
        """R1: a crash of the token-bearing CLI process leaks neither core nor environ.

        Positive control: the same synthetic marker passed in the exec-time
        environment must appear in COREDUMP_ENVIRON, proving the check works.
        """
        import resource

        marker = "BWSESSIONSYNTHETIC" + secrets.token_hex(12)
        with tempfile.TemporaryDirectory() as scratch:
            crash = os.path.join(scratch, "crash.js")
            with open(crash, "w") as handle:
                handle.write("setTimeout(() => process.abort(), 50);\n")

            def no_core():
                resource.setrlimit(resource.RLIMIT_CORE, (0, 0))

            env = {"PATH": "/usr/bin", "HOME": scratch}
            control = subprocess.Popen([_bw.NODE, crash], env=dict(env, BW_SESSION=marker),
                                       preexec_fn=no_core)
            control.wait(timeout=30)
            read_fd, write_fd = os.pipe()
            os.write(write_fd, marker.encode() + b"\n")
            os.close(write_fd)
            guarded = subprocess.Popen([_bw.NODE, _bw.BOOTSTRAP, crash, str(read_fd)], env=env,
                                       pass_fds=(read_fd,), preexec_fn=no_core)
            os.close(read_fd)
            guarded.wait(timeout=30)
        self.assertEqual(control.returncode, -signal.SIGABRT)
        self.assertEqual(guarded.returncode, -signal.SIGABRT)
        entries = {}
        deadline = time.monotonic() + 30
        while len(entries) < 2 and time.monotonic() < deadline:
            for proc in (control, guarded):
                out = subprocess.run(
                    ["journalctl", "-q", "-o", "json", "--output-fields=COREDUMP_ENVIRON,"
                     "COREDUMP_FILENAME,COREDUMP_RLIMIT", f"COREDUMP_PID={proc.pid}",
                     f"COREDUMP_UID={os.getuid()}"],
                    capture_output=True, timeout=30, check=False).stdout
                if out.strip():
                    entries[proc.pid] = json.loads(out.splitlines()[-1])
            time.sleep(1)
        if len(entries) < 2:
            self.skipTest("systemd-coredump journal entries not found")
        control_entry, guarded_entry = entries[control.pid], entries[guarded.pid]
        self.assertIn(marker, str(control_entry.get("COREDUMP_ENVIRON")), "positive control failed")
        self.assertNotIn(marker, json.dumps(guarded_entry))
        for entry in (control_entry, guarded_entry):
            self.assertNotIn("COREDUMP_FILENAME", entry)  # RLIMIT_CORE=0: no core stored
            self.assertEqual(entry.get("COREDUMP_RLIMIT"), "0")


if __name__ == "__main__":
    live = "--live" in sys.argv
    if live:
        sys.argv.remove("--live")
    else:
        del LiveTests
    unittest.main(verbosity=1)

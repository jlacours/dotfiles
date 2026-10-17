"""bw-session-guard: startup reconcile, lock on sleep, screen-lock handling.

Logs fixed messages only.  A 60 s tick re-checks the absolute and
CLOCK_BOOTTIME deadlines and the expiry timer, so expiry never depends on
the transient timer alone.

Sleep: access is denied the moment PrepareForSleep(true) arrives (tombstone),
then the profile lock is attempted inside logind's InhibitDelayMaxUSec
budget, read at startup.  A delay inhibitor is a bounded grace period, so
completion before sleep is best effort; whatever is left is finished after
resume while the tombstone keeps readers denied.  Independently of this
service, any suspend since unlock invalidates the record (BOOTTIME -
MONOTONIC), so a missed signal cannot leave a usable session.
"""

import collections
import os
import sys
import time

from jeepney import DBusAddress, MatchRule, Properties, new_method_call
from jeepney.bus_messages import message_bus
from jeepney.io.blocking import open_dbus_connection

LOGIN1 = "org.freedesktop.login1"
MANAGER = DBusAddress("/org/freedesktop/login1", bus_name=LOGIN1,
                      interface="org.freedesktop.login1.Manager")
TICK_SECONDS = 60
DEFAULT_DELAY_SECONDS = 5.0
DELAY_MARGIN_SECONDS = 0.75


def log(message):
    print(f"bw-session-guard: {message}", file=sys.stderr, flush=True)


class Guard:
    def __init__(self, authority):
        self.authority = authority
        self.conn = None
        self.inhibitor = None
        self.delay_seconds = DEFAULT_DELAY_SECONDS

    def _call(self, msg, timeout=5):
        return self.conn.send_and_get_reply(msg, timeout=timeout)

    def take_inhibitor(self):
        if self.inhibitor is not None or not self.authority.config.lock_on_suspend:
            return
        try:
            reply = self._call(new_method_call(
                MANAGER, "Inhibit", "ssss",
                ("sleep", "bw-session-guard", "Lock the Bitwarden session before sleep", "delay")))
            body = reply.body
            self.inhibitor = body[0] if body else None
        except Exception:
            self.inhibitor = None
            log("sleep delay inhibitor unavailable; locking on PrepareForSleep without it")

    def release_inhibitor(self):
        if self.inhibitor is not None:
            try:
                self.inhibitor.close()
            except Exception:
                pass
            self.inhibitor = None

    def read_delay_budget(self):
        """logind's effective InhibitDelayMaxUSec, in seconds."""
        try:
            reply = self._call(Properties(MANAGER).get("InhibitDelayMaxUSec"))
            (_signature, usec), = reply.body
            if isinstance(usec, int) and usec > 0:
                self.delay_seconds = usec / 1_000_000
        except Exception:
            log("InhibitDelayMaxUSec unavailable; assuming 5 s")
        return self.delay_seconds

    def sleep_budget(self):
        return max(self.delay_seconds - DELAY_MARGIN_SECONDS, 0.5)

    def _session_uid(self, path):
        address = DBusAddress(path, bus_name=LOGIN1, interface="org.freedesktop.login1.Session")
        reply = self._call(Properties(address).get("User"))
        (_signature, (uid, _user_path)), = reply.body
        return uid

    def handle(self, msg):
        member = msg.header.fields.get(3)  # HeaderFields.member
        if member == "PrepareForSleep":
            (starting,) = msg.body
            config = self.authority.config
            if starting:
                if config.lock_on_suspend:
                    try:
                        ok = self.authority.revoke("suspend", budget=self.sleep_budget())
                    finally:
                        self.release_inhibitor()
                    log("locked before sleep" if ok
                        else "access denied; profile lock completes after resume")
                else:
                    self.authority.cancel_unlocks()
                    self.release_inhibitor()
            else:
                if config.lock_on_suspend and self.authority.has_records():
                    ok = self.authority.revoke("suspend")
                    log("locked after resume" if ok else "lock after resume incomplete")
                self.authority.check_expiry()
                self.take_inhibitor()
        elif member == "Lock":
            path = msg.header.fields.get(1)  # HeaderFields.path
            try:
                mine = self._session_uid(path) == os.getuid()
            except Exception:
                mine = False
            if not mine:
                return
            # A prompt in flight never commits behind a locked screen.
            self.authority.cancel_unlocks()
            if self.authority.config.lock_on_screenlock:
                ok = self.authority.revoke("screenlock")
                log("locked with the screen" if ok else "screen-lock lock incomplete")

    def run(self):
        ok = self.authority.reconcile()
        log("startup reconcile complete" if ok else "startup reconcile left cleanup pending")
        if self.authority.config.idle_lock_min:
            log("IDLE_LOCK_MIN is not enforced by the guard; use a hypridle listener (see README)")
        self.conn = open_dbus_connection(bus="SYSTEM", enable_fds=True)
        rules = [
            MatchRule(type="signal", interface="org.freedesktop.login1.Manager",
                      member="PrepareForSleep", path="/org/freedesktop/login1"),
            MatchRule(type="signal", interface="org.freedesktop.login1.Session", member="Lock"),
        ]
        queue = collections.deque(maxlen=32)
        handles = [self.conn.filter(rule, queue=queue) for rule in rules]
        for rule in rules:
            self._call(message_bus.AddMatch(rule))
        budget = self.read_delay_budget()
        self.take_inhibitor()
        log(f"watching logind (sleep budget {self.sleep_budget():.2f} s of {budget:.2f} s)")
        try:
            while True:
                try:
                    msg = self.conn.recv_until_filtered(queue, timeout=TICK_SECONDS)
                except TimeoutError:
                    try:
                        self.authority.check_expiry()
                        self.take_inhibitor()
                    except Exception:
                        log("periodic check failed")
                    continue
                try:
                    self.handle(msg)
                except Exception:
                    log("event handling failed")
                    time.sleep(1)
        finally:
            for handle in handles:
                handle.close()
            self.release_inhibitor()

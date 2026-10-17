"""Desktop glue: fuzzel picker and passive, rate-limited reminders."""

import json
import os
import subprocess
import time

from ._core import Error, Expired

LOGIN1 = "org.freedesktop.login1"

REMIND_MIN_INTERVAL = 600  # seconds between any two reminders
NOTIFY_TIMEOUT_MS = 15000


def _home_bin(name):
    return os.path.join(os.path.expanduser("~"), ".local", "bin", name)


def gui_env():
    """Caller environment for GUI helpers, minus anything Bitwarden-specific."""
    return {k: v for k, v in os.environ.items()
            if not k.startswith(("BW_", "BITWARDENCLI_")) and k not in ("NODE_OPTIONS",)}


# -- picker -----------------------------------------------------------------
PICK_IDLE_SECONDS = 120  # the menu closes itself after this long
PICK_POLL_SECONDS = 0.25


def pick(authority):
    """Run fuzzel over sanitized labels of one generation.

    Returns (item ID, generation), or None on cancel, timeout, lock, expiry
    or re-unlock while the menu was open (fuzzel is killed at once).
    """
    state = authority.status()
    if state.get("state") != "unlocked":
        raise Expired("Vault locked or session expired")
    generation, deadline = state["generation"], state["deadline"]
    epoch = authority.epoch()
    entries = authority.list_entries(generation=generation)
    if not entries:
        return None
    labels = "".join(label + "\n" for label, _item_id in entries).encode("utf-8")
    try:
        proc = subprocess.Popen(
            ["fuzzel", "--dmenu", "--index", "--cache=/dev/null",
             "--prompt=bitwarden ❯ ", "--placeholder=search vault"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env=gui_env())
    except OSError:
        raise Error("fuzzel could not start") from None
    try:
        try:
            proc.stdin.write(labels)
            proc.stdin.close()
        except OSError:
            pass
        del labels
        give_up = time.monotonic() + PICK_IDLE_SECONDS
        while proc.poll() is None:
            if (authority.revoked_since(epoch) or authority.clock.wall() >= deadline
                    or time.monotonic() >= give_up):
                return None
            time.sleep(PICK_POLL_SECONDS)
        output = proc.stdout.read(64)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        proc.stdout.close()
    if proc.returncode != 0:
        return None
    # The choice only counts if the generation it was made under is still current.
    if authority.revoked_since(epoch):
        return None
    authority.session(generation)
    text = output.decode("ascii", "replace").strip()
    if text == "-1" or text == "":
        return None
    if not (text.isascii() and text.isdigit() and len(text) <= 7):
        raise Error("Unexpected picker output")
    index = int(text)
    if not 0 <= index < len(entries):
        raise Error("Unexpected picker output")
    return entries[index][1], generation


# -- reminder suppression ---------------------------------------------------
def hyprlock_running():
    uid = os.getuid()
    try:
        pids = [p for p in os.listdir("/proc") if p.isdigit()]
    except OSError:
        return True
    for pid in pids:
        try:
            if os.stat(f"/proc/{pid}").st_uid != uid:
                continue
            with open(f"/proc/{pid}/comm", encoding="utf-8", errors="replace") as handle:
                if handle.read(32).strip() == "hyprlock":
                    return True
        except OSError:
            continue
    return False


def game_mode_active():
    script = os.path.join(os.path.expanduser("~"), ".config", "hypr", "scripts", "game-mode.sh")
    if not os.access(script, os.X_OK):
        return False
    try:
        proc = subprocess.run([script, "status"], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              timeout=3, check=False)
    except subprocess.TimeoutExpired:
        return True  # mid-transition: stay quiet
    except OSError:
        return False
    return proc.stdout.strip() == b"on"


def fullscreen_active():
    try:
        proc = subprocess.run(["hyprctl", "-j", "activewindow"], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              timeout=2, check=False)
        window = json.loads(proc.stdout or b"{}")
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return False
    if not isinstance(window, dict):
        return False
    value = window.get("fullscreen")
    return bool(value) and value not in ("0", 0)


def _logind_display_active(timeout=2):
    """This user's graphical logind session is Active and not LockedHint."""
    from jeepney import DBusAddress, Properties
    from jeepney.io.blocking import open_dbus_connection

    with open_dbus_connection(bus="SYSTEM") as conn:
        user = DBusAddress(f"/org/freedesktop/login1/user/_{os.getuid()}", bus_name=LOGIN1,
                           interface="org.freedesktop.login1.User")
        (_sig, (session_id, path)), = conn.send_and_get_reply(
            Properties(user).get("Display"), timeout=timeout).body
        if not session_id:
            return False
        session = DBusAddress(path, bus_name=LOGIN1, interface="org.freedesktop.login1.Session")
        (_sig, active), = conn.send_and_get_reply(Properties(session).get("Active"), timeout=timeout).body
        (_sig, locked), = conn.send_and_get_reply(
            Properties(session).get("LockedHint"), timeout=timeout).body
        return active is True and locked is False


def desktop_unlocked():
    """Shared gate for prompts and desktop unlock commits; False when unsure.

    hyprlock started directly (hypridle) does not tell logind, so the process
    check comes first; logind covers VT switches and `loginctl lock-session`.
    """
    if not os.environ.get("WAYLAND_DISPLAY"):
        return False
    if hyprlock_running():
        return False
    try:
        return _logind_display_active()
    except Exception:
        return False


def suppressed():
    if not desktop_unlocked():
        return True
    return game_mode_active() or fullscreen_active()


# -- reminder ---------------------------------------------------------------
def remind(authority):
    """Passive "Bitwarden locked" notification, at most once per lock period.

    Never opens a password window by itself: the notification's action is the
    deliberate step, and it is ignored unless the desktop is active and unlocked.
    """
    if not authority.config.remind:
        return "disabled"
    if authority.status().get("state") != "locked":
        return "not-locked"
    if suppressed():
        return "suppressed"
    with authority.serialized(2) as acquired:
        if not acquired:
            return "busy"
        count = authority.epoch()
        last = authority._read_json("remind") or {}
        now = authority.clock.boottime()
        last_at = last.get("at") if isinstance(last.get("at"), (int, float)) else -1e12
        if last.get("count") == count or 0 <= now - last_at < REMIND_MIN_INTERVAL:
            return "rate-limited"
        authority._write_json("remind", {"count": count, "at": now})
    _spawn_notification()
    return "sent"


def _spawn_notification():
    pid = os.fork()
    if pid:
        os.waitpid(pid, 0)
        return
    try:
        os.setsid()
        if os.fork():
            os._exit(0)
        devnull = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 2):
            os.dup2(devnull, fd)
        proc = subprocess.run(
            ["notify-send", "--app-name=Bitwarden", "--urgency=low",
             f"--expire-time={NOTIFY_TIMEOUT_MS}", "--icon=dialog-password",
             "--action=unlock=Unlock", "Bitwarden locked",
             "Unlock from the bar when you need the vault."],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            env=gui_env(), timeout=NOTIFY_TIMEOUT_MS / 1000 + 15, check=False)
        if proc.stdout.strip() == b"unlock" and desktop_unlocked():
            card = _home_bin("bw-unlock-card")
            if os.access(card, os.X_OK):
                subprocess.Popen([card], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, env=gui_env(), start_new_session=True)
    except BaseException:
        pass
    finally:
        os._exit(0)

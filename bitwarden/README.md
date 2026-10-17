# Bitwarden CLI session authority

This Stow package installs:

| Path | Purpose |
|---|---|
| `~/.local/lib/bwsession/` | Python package: the single authority for the CLI session |
| `~/.local/bin/bw-session` | CLI over that package (status, unlock, lock, pick, remind, guard) |
| `~/.local/bin/bw` | Shim ahead of `/usr/bin/bw`: an allowlist of commands, run under the managed session |
| `~/.config/bw-session.conf` | Policy (`KEY=VALUE` data, parsed with bounds, never sourced) |
| `~/.config/systemd/user/bw-session-guard.service` | Reconciles at startup; locks on sleep; cancels prompts on screen lock |

## What it guarantees, and what it does not

**Same-user agents and processes are not isolated from an unlocked vault.**
Anything running as this Unix user can read the unlocked login keyring, the
child environment of a running `bw`, the clipboard, or simply run
`/usr/bin/bw` itself. `bw lock` clears *this profile's* reusable unlock state;
it does not revoke copies already made (a token plus a pre-lock copy of the
profile data, or already decrypted entries). Real agent isolation needs a
separate identity or an enforced sandbox, not a wrapper.

What this layer does provide:

- The master password is never stored. It reaches `bw unlock` through an
  anonymous pipe (`--passwordfile /dev/fd/N`), never argv, environment or disk.
- The session token is never in argv and never in an exec'd environment. It
  reaches the CLI over an anonymous pipe: `bootstrap.js` reads it and sets
  `process.env.BW_SESSION` inside node before loading the CLI, so
  `/proc/PID/environ` and systemd-coredump's `COREDUMP_ENVIRON` journal field
  never contain it. It is never exported to the desktop or systemd environment
  and never printed (`--raw`, `--session` and `bw login` are refused).
- Only the default profile (`~/.config/Bitwarden CLI`) is managed. Children get
  no profile variables; a caller whose `BITWARDENCLI_APPDATA_DIR` or
  `XDG_CONFIG_HOME` selects another profile is refused. Use `/usr/bin/bw` for
  other profiles (unmanaged).
- One keyring record holds token, random 8-hex generation, issue time,
  deadline, boot ID, a `CLOCK_BOOTTIME` stamp and the suspend total at unlock.
  Malformed, duplicate or legacy records deny access and trigger a lock. With
  no record, the profile is treated as unmanaged and locked with a real
  `bw lock` before `locked` is reported (once per lock period, then every 5
  minutes while polled).
- Transitions are transactional. An unlock writes a marker before `bw unlock`
  runs and becomes visible only after the record is stored *and* the expiry
  timer is armed; until then every reader denies. Any failure, timeout,
  cancellation or interruption runs a real `bw lock`; a killed unlock is found
  by its marker and revoked by the next reader or the guard.
- Unlock attempts carry a cancellation ticket, taken before they wait for
  anything. `cancel_unlocks()`, a lock, a suspend or a screen lock after the
  ticket aborts the attempt. The final check and the commit share a short lock
  with cancellation, so each cancel either lands before the commit or comes
  after it. A caller that abandons an attempt whose unlock then succeeds
  revokes that attempt's generation with `lock_generation()`.
- `status()` and session reads only report a generation that is still current
  when they return. A revocation during the call is caught by the lock-period
  check, and the record is checked again. The whole `status()` call is bounded
  to 8 s.
- A lock first writes a tombstone that every reader honours, then cleans up
  under the transition lock. If that lock is held, the profile is still
  locked and the in-flight unlock aborts before commit; `bw-session lock`
  reports the incomplete cleanup (exit 2) instead of claiming success.
- Absolute lifetime (`TTL_HOURS`, default 8), fixed at unlock and never
  renewed by polls or background use. Expiry is enforced by a transient
  `bwsession-expire-<generation>.timer` (unlock fails unless it was armed), by
  every request, and by the guard's 60-second check, which also re-arms a
  missing timer. Wall-clock rollback, suspend and reboot cannot extend it; a
  reboot ends the session.
- Session commands are supervised: the CLI child is killed as soon as the
  session is locked, replaced or expires, and its output is released only if
  the same generation is still current afterwards. The menu picker is bound to
  one generation the same way and closes itself after 2 minutes.
- Status and background paths never unlock the keyring or show a keyring
  prompt; a locked login keyring is reported as `keyring-locked`.
- No password window ever opens by itself: on expiry the bar chip dims and at
  most one passive "Bitwarden locked" notification per lock period appears
  (suppressed while hyprlock runs, in game mode, or with a fullscreen window).
- Crashes: `RLIMIT_CORE=0` is set for the whole process tree, and
  systemd-coredump honours it (`%c`), so no core image is stored. The Python
  processes are also non-dumpable (`PR_SET_DUMPABLE=0`). The node CLI process
  cannot call `prctl`, so it stays dumpable; its journal crash metadata is
  still free of the token, because the token is not in its exec-time
  environment. A synthetic-token crash test (`--live`) checks both. Node
  diagnostic reports are switched off in the bootstrap. Errors are fixed
  messages without tracebacks.
- Prompts: desktop unlocks (the unlock card) are refused while the desktop is
  locked (hyprlock running, or the logind session inactive or locked) and
  never commit if it locks meanwhile. The guard also cancels in-flight
  unlocks on logind `Lock`, even when `LOCK_ON_SCREENLOCK=no`.

## Policy: `~/.config/bw-session.conf`

| Key | Default | Meaning |
|---|---|---|
| `TTL_HOURS` | `8` | Absolute lifetime, 1..24. Lowering it also shortens a running session. |
| `LOCK_ON_SUSPEND` | `yes` | Any suspend ends the session. More than 50 ms of suspended time counts; that tolerance only absorbs the gap between the two clock reads. Readers deny after resume whether or not the guard ran. The guard denies access the moment `PrepareForSleep` arrives. It then tries to lock the profile within logind's `InhibitDelayMaxUSec` (5 s here), best effort. Every blocking step is capped by that budget; a killed child can add up to 0.5 s to be reaped. Anything left over stays pending, with access denied, and finishes after resume. |
| `LOCK_ON_SCREENLOCK` | `no` | Guard locks on logind `Lock` for this user's session (`loginctl lock-session`; a hyprlock started directly does not emit it). |
| `IDLE_LOCK_MIN` | `0` | Not measured by the guard. To lock on idle, add a hypridle listener (below). |
| `REMIND` | `yes` | Passive locked-reminder notifications. |

Idle lock via `hypridle.conf` (the timeout is in seconds):

```ini
listener {
    timeout = 900
    on-timeout = ~/.local/bin/bw-session lock --reason idle
}
```

Trade-off: while the vault is locked, background consumers such as
`vdirsyncer` (`bw get password …`) fail until you unlock again.

## Commands

```text
bw-session status --json   {"schema":1,"state":"unlocked|locked|unauthenticated|keyring-locked|error",
                            "deadline":<epoch|null>,"generation":"<8 hex>|null","message":"<fixed text>"}
bw-session unlock --password-fd N   exit 0 ok, 1 wrong password, 2 other error
                           (desktop-gated when WAYLAND_DISPLAY is set and not over SSH)
bw-session lock [--reason manual|expired|suspend|screenlock|idle]
bw-session pick [--with-generation]
                           fuzzel (--index, --cache=/dev/null) over sanitized
                           "name — username" labels; prints one item ID (or "ID GENERATION"),
                           exit 1 cancel/lock/expiry/re-unlock while open, 2 error
bw-session remind          passive, rate-limited "locked" notification (hypridle on-resume)
bw-session guard           service loop for bw-session-guard.service
```

Python (`sys.path` needs `~/.local/lib`):

```python
import bwsession
bwsession.status()                         # same schema as above, never prompts
ticket = bwsession.unlock_ticket()         # when the attempt starts, before any worker
generation = bwsession.unlock(password_bytes, ticket=ticket)  # desktop-gated; raises
                                           #   WrongPassword / Error ("Unlock cancelled")
bwsession.unlock(password_bytes, desktop=False)  # terminal/SSH prompt
bwsession.lock(reason="manual")            # raises bwsession.Error if cleanup is pending
bwsession.lock_generation(generation)      # revoke an abandoned attempt's session
bwsession.meta(item_id)                    # {"name", "username", "uris"}, sanitized
bwsession.secret(item_id, "password", generation)  # bytes; raises bwsession.Expired
bwsession.pick_bound()                     # (item_id, generation) or None
bwsession.desktop_unlocked()               # shared gate for prompts
bwsession.cancel_unlocks()                 # abort every attempt not yet committed
```

Every function may be called from several threads at once. Secret Service
calls on the shared connection are serialized per connection, with a bounded
wait, because Jeepney's blocking connection cannot have two requests in
flight. Transitions use `flock`, runtime files are replaced atomically, and
deadlines are per thread.

The `bw` shim accepts a small grammar. Leading global options `--pretty`,
`--response`, `--quiet`, `--nointeraction` and `--cleanexit` are forwarded.
`--session`, `--raw`, `--passwordenv`, `--passwordfile` and `--apikey` are
refused wherever they appear.

| Command | Behaviour |
|---|---|
| `get <item\|username\|password\|uri\|totp\|notes\|…> <id>` | supervised, with the managed session (vdirsyncer's `bw get password <id>` path; stdout bytes unchanged) |
| `list <items\|folders\|…> [--search/--url/--folderid/--collectionid/--organizationid X] [--trash]` | supervised |
| `sync [-f] [--last]`, `status` | supervised (`status` without a session when locked) |
| `unlock`, `unlock --check` | prompts in an interactive terminal / reports the managed state; no password argument |
| `lock`; `logout` | locks everything (must succeed); `logout` then runs without a session |
| `login` | refused: run `/usr/bin/bw login`, then `bw unlock` |
| `serve` | refused (it would hand the session to a long-lived server) |
| `help`, `--version`, `generate`, `encode`, `completion` | passed through without a session |
| anything else (`export`, `create`, `edit`, `config`, …) | refused; use `/usr/bin/bw` directly (unmanaged) |

When locked, session commands fail fast with exit 1. Non-interactive callers
also trigger the passive reminder.

## Install

```bash
yay -S --needed bitwarden-cli gnome-keyring libsecret python-secretstorage nodejs
./install.sh --dry-run bitwarden
```

Do not just stow this package on a machine that runs the old wrapper. Stowing
it links `bw-session`, and the bar and hypridle start calling it at once. The
switch-over is a resumable, checked transaction, run with the reviewed
activation script. It keeps its state in `~/.local/state/bw-activation`: an
activation lock, the phase, the inventory of stopped consumers, and a
read-only, hash-checked backup of the old wrapper taken once.

1. Preconditions. Then stop `vdirsyncer.timer` (and wait for a running
   `vdirsyncer.service`), `hypridle.service` and the bar. Wait until no known
   caller is running: the old wrapper, the CLI, the cards, the menu,
   `bw-session` or vdirsyncer.
2. Back up the old wrapper. Install the library and launchers
   (`./install.sh bitwarden tui`) and check the links, import and unit.
3. Replace `bw` by atomic rename, then `daemon-reload`.
4. Migrate. The state must be `locked`/`unauthenticated`, with no
   `pending`/`txn` and no legacy item.
5. Restart the guard. Check its journal lines and its delay inhibitor.
6. Unlock deliberately, and confirm exactly one expiry timer.
7. Acceptance:
   - a bounded vdirsyncer run succeeds while unlocked;
   - after `bw lock`, the exact vdirsyncer command gets the fixed denial
     (exit 1, empty stdout);
   - the unit then fails with `exit-code` within 60 s.
8. Restart the consumers, with vdirsyncer last.

Any failure, `INT` or `TERM` stops the run. Before installation, nothing has
changed, so the paused consumers are restarted. From installation on, every
consumer stays stopped (even ones already restarted) and the session is
revoked. If revocation fails, the guard and the authority stay in place,
access stays denied, and nothing is rolled back. Fix the cause, then
`--resume`; `--status` shows where the run is.

Rollback is never automatic. `--rollback` asks for confirmation, stops the
consumers, and requires a confirmed lock. Only then does it disable the guard,
stop the expiry timers and restore the hash-checked backup by atomic rename.
The consumers stay stopped until the new files are unstowed. Never restore or
copy cached secrets.

The first run of the new authority finds the old wrapper's keyring item
(`application=bitwarden-cli-session`), runs `bw lock` and deletes it. It only
does this for the real home directory. Unlock once more afterwards.

## Troubleshooting

- `bw-session status` shows `error`. One of these:
  - The Secret Service is unreachable.
  - A lock is still pending (`$XDG_RUNTIME_DIR/bwsession/pending`, which holds
    no secrets). Access stays denied, and the next call or the guard retries.
  - The caller selected another profile.
- `keyring-locked`: log in graphically so PAM unlocks the login keyring.
- `journalctl --user -u bw-session-guard` shows fixed status lines only.
- `/usr/bin/bw` bypasses the authority entirely. An unmanaged session it
  creates is locked by the next status poll that finds no managed record.

## Tests

```bash
python3 -I scripts/test-bwsession.py          # fake bw, memory keyring, fake clock
python3 -I scripts/test-bwsession.py --live   # + synthetic keyring item, far-future
                                              #   timer, logind budget, scratch home, and a
                                              #   synthetic-token crash checked in the journal
```

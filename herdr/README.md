# External Herdr control

## Compact state icons

`herdr-agent-status` shows a state icon before each name on the tab bar, keeping
symbol glyphs away from the terminal's right edge. Working agents use
the rotating `◐◓◑◒` icon; blocked, done, idle, and unknown agents use `!`, `✓`,
`○`, and `?`. The helper refreshes once per second, Herdr's minimum command
interval. It reads current agent states without changing them or sending input.
The agent in the focused pane is bracketed (`[◐ codex]`) and placed first so it
stays visible when the row's eight-agent limit is reached. When the focused pane
has no agent, no entry is bracketed. Other agents retain attention ordering.

The native `status_indicators = "symbols"` setting adds distinct colored
symbols to Herdr's own state badges. The command statusline uses the tab bar's
text color: Herdr removes ANSI escape styling from command output.

## External callers

`herdr-control` is a narrow entry point for a local CLI harness or a terminal
tool such as Hermes. It uses the installed `herdr` CLI, its documented Unix
socket API for local prompts, and saved SSH machine forwarding. It does not set
`HERDR_ENV`, open a network listener, launch a Herdr server, create panes, or fall back to another
machine.

The helper lets an explicitly requested Herdr task use the supported CLI from
outside a managed pane. That corrects an overly strict caller-context check; it
does not grant new system permissions. The local socket remains protected by
its filesystem ownership and mode. Remote control uses only an already saved,
enabled Herdr machine profile, with SSH authentication and the user's normal
host-key verification. Both Herdr installations must support the API, and the
remote server must already be running and compatible.

## Read-only discovery

```sh
herdr-control status
herdr-control list
herdr-control get --target w1:p1
```

`list` returns workspace, pane, and agent identifiers and lifecycle summaries.
It omits paths, terminal titles, and terminal contents. `get` accepts a pane ID
and returns a similarly limited pane summary. IDs are server-scoped; discover
them again for each selected machine. Nothing defaults to the focused pane.

## Explicit pane reads

```sh
herdr-control read --target w1:p1 --lines 80
```

Terminal output can contain private conversation text or other sensitive data.
Use `read` only when the task calls for that output, and keep it out of routine
status checks.

## Waiting and sending

```sh
herdr-control wait --target w1:p1 --timeout 120000
printf '%s\n' 'The explicitly requested task' |
  herdr-control prompt --target w1:p1 --confirm-send --wait --timeout 120000
```

Prompt text is accepted only on stdin. Local prompts travel over the existing
Unix socket, without placing their text in a subprocess argument list. The
socket must belong to the caller and exclude group and other access. This
local transport requires Unix.

Calls with `--machine` use Herdr's supported SSH CLI forwarding; that CLI
requires prompt text as an argument, which may be visible to local process
inspection subject to the system's permissions. A Matrix conversation whose
gateway runs on this machine can use the local socket path and avoid that
limitation.

Sending requires both an explicit pane ID and `--confirm-send`; the helper checks that Herdr currently
reports the agent as `idle` or `done`. It refuses
`working`, `blocked`, `unknown`, or unavailable states. The check and send are
separate operations, so another client could change the state between them;
Herdr's own blocked-agent rejection remains in force. If a send reports an
error or times out, inspect the target before retrying because delivery may be
ambiguous.

## Saved SSH machines

Add and verify a machine profile through Herdr's normal setup outside this
helper. Then pass the exact enabled saved profile ID or label:

```sh
herdr-control list --machine lab-pi
herdr-control get --machine lab-pi --target w1:p1
```

The helper checks the requested selector against `herdr machine list --json`
and passes it as an argv element to `herdr --machine`. It never accepts an SSH
hostname, shell fragment, or arbitrary socket path as a remote destination.
Herdr's machine forwarding does not install or start a remote server. Do not
create profiles or accept host-key changes in response to untrusted inbound
messages.

## Harness instruction

Use this helper only when the user explicitly asks to inspect or control
Herdr. Do not require `HERDR_ENV=1` for an external CLI invocation. Start with
`status` or `list`, choose an explicit pane ID, and keep discovery output
limited to the task. Use `read` only when needed; send prompts only after the
user's task authorizes them and with `--confirm-send`. Never substitute a
focused pane, infer a remote machine, or relay untrusted message content as a
prompt without user authorization.

## Hermes TUI state detection

The local `agent-detection/hermes.toml` override preserves the upstream rules
from `2026.07.24.1` and raises the idle OSC-title rule above screen-text rules.
Hermes TUI emits a live title marker for idle, working, and approval states.
Retained approval or cancel text therefore cannot turn an idle TUI into a
false blocked or working agent. The classic CLI's screen rules remain active
when no state marker is present.

Apply detector changes without restarting running panes:

```sh
herdr server reload-agent-manifests
herdr agent explain PANE_ID --verbose
```

This local override shadows automatic remote Hermes manifest updates. Compare
it with a future upstream manifest before updating or removing it; the only
rule change is the priority of `osc_title_idle`.

## AGY state detection

The local `agent-detection/agy.toml` preserves remote manifest `2026.06.24.1`
and adds a working rule for the active-turn `esc to cancel` footer. AGY can
briefly replace its spinner between tools and model output; the footer keeps
those gaps from becoming false completion notifications. Permission and
background-task rules remain active.

This override also shadows future remote manifest updates. Compare it with
the upstream AGY manifest before updating or removing it. Terminal lifecycle
states are hints; collect the helper's report before declaring a task done.

## Foreground tab titles

The tab bar calls the optional `juju.tab-titles.refresh` plugin action every
three seconds. Install or link [`jlacours/herdr-tab-titles`](https://github.com/jlacours/herdr-tab-titles)
to update automatically managed titles when foreground programs start or exit.
The plugin preserves custom labels and resets managed tabs to their shell name
after a command ends. It changes tab labels without altering terminal OSC titles.
If the plugin is absent, this silent command has no effect. Polling runs while
a client renders the tab bar; commands shorter than the interval may not appear.

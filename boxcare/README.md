# Boxcare

`boxcare` performs the same bounded maintenance check across the machines in
`~/.config/boxcare/hosts.json`. The tracked inventory contains logical host IDs
and SSH aliases only; addresses, users, ports, keys, and credentials stay in
the machine-local SSH configuration.

## Safety model

The default action is a read-only audit:

```bash
boxcare
boxcare audit
```

Audits collect basic reachability, operating-system, uptime/load, disk/inode,
listener, failed-service, and available-update signals. Audit checks run
concurrently (`jobs_audit` defaults to four), while real updates are
deliberately serialized (`jobs_update` defaults to one). Connection and
command timeout thresholds keep an offline box from wedging the entire run.
`transaction_warn_after_s` remains accepted in the schema for future
update-progress reporting, but is not currently enforced and does not add an
update timeout.

Updates require the explicit `update` subcommand. Preview the commands first:

```bash
boxcare update --dry-run
boxcare update
```

The dry run may contact selected hosts to detect their distribution and inspect
cached package metadata, but it does not refresh metadata or mutate remote
state. A real update uses each host's detected platform: Debian-family boxes run
`apt-get update` followed by `apt-get upgrade`; Arch runs `pacman -Syu`
against configured binary repositories only; Termux uses `pkg upgrade`.
Boxcare never removes packages, cleans caches, edits repositories, changes SSH
configuration, installs keys, changes users or firewall rules, restarts or
enables services, or reboots a host. Tiny Debian goblins remain strictly
outside the threat model.

Boxcare never invokes a privilege-escalation tool. Audits use only the access
available to the SSH login, and updates refuse to run unless that login is
already root (Termux remains unprivileged by design). Use a dedicated root SSH
alias only when you deliberately want Boxcare to update that host.

SSH uses batch mode and strict host-key checking. Add and verify each host key
through normal SSH before including the machine in a run; Boxcare will not
accept a new or changed key on your behalf.

## Inventory and selection

Inventory schema version 1 defines defaults and a `hosts` list. Each host has a
stable `id`, optional display `label`, `ssh_alias`, a `distro` hint (`auto` in
the tracked inventory), `tags`, and an `enabled` flag. `expected_mounts` and
the TCP/UDP listener allowlists are accepted schema fields, but the current
audit does not evaluate them; the listener check reports observed listeners
without comparing them with those lists or changing firewall rules. Optional
`important_units` is the only per-host check customization currently applied:
it adds services whose state matters on a particular box. The tracked
Pixel/Termux entry is disabled because it is normally offline. Enable it in a
machine-local inventory when needed; disabled hosts are excluded from ordinary
selection.

Select one or more hosts or tags by repeating the option:

```bash
boxcare audit --host pi5 --host vps
boxcare audit --tag pi
boxcare update --dry-run --tag server
boxcare audit --jobs 2
boxcare audit --inventory /path/to/hosts.json
```

Host and tag filters are combined: a selected host must satisfy the supplied
host IDs and tags. Unknown IDs/tags, an empty selection, duplicate host IDs,
unsupported platforms, and invalid limits are errors rather than silent skips.

## Output

Human-readable tables are the default. Machine-readable modes keep routine
automation out of the land of heroic text parsing:

```bash
boxcare audit --format json
boxcare audit --format jsonl
```

JSON emits one document containing run metadata and host results. JSONL emits
one self-contained result per line plus a final summary. Diagnostics go to
standard error so standard output remains parseable. A non-zero exit status
means at least one selected host reported a security/health warning, failed,
timed out, or returned an incomplete result.

## Installation

The package is discovered automatically by the repository installer:

```bash
cd ~/.dotfiles
./install.sh --dry-run boxcare
./install.sh boxcare
```

The executable uses Python's standard library and the system `ssh` client. On
Arch, install those runtime dependencies with:

```bash
sudo pacman -S --needed python openssh
```

Review the inventory and confirm every alias manually before the first audit:

```bash
ssh pi5 true
boxcare audit --host pi5
```

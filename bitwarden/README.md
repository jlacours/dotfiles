# Bitwarden CLI session wrapper

This Stow package installs `~/.local/bin/bw` ahead of `/usr/bin/bw`.

The wrapper stores Bitwarden CLI's temporary `BW_SESSION` token in the active
GNOME Keyring. It never stores the master password. After one interactive
`bw unlock`, authenticated `bw` commands in new shells and automation reuse the
keyring-backed session instead of prompting repeatedly.

A stale or missing session fails immediately in non-interactive commands rather
than hanging on a hidden master-password prompt. `bw lock` and `bw logout` clear
the keyring entry.

## Requirements

```bash
yay -S --needed bitwarden-cli gnome-keyring libsecret
systemctl --user start gnome-keyring-daemon.service
```

## Install

```bash
./install.sh --dry-run bitwarden
./install.sh bitwarden
bw unlock
```

Use `/usr/bin/bw` to bypass the wrapper for troubleshooting.

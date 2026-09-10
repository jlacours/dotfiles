# Borg backup package

This Stow package installs a user-level Borg backup script, its exclusion
patterns, and a daily systemd timer. Repository locations, credentials,
machine-specific exclusions, and optional snapshot commands remain local.

## Configure

Install Borg and stow the package:

```bash
sudo pacman -S --needed borg
cd ~/.dotfiles
./install.sh borg
```

Create the machine-local configuration from the tracked example:

```bash
cp ~/.config/borg/backup.env.example ~/.config/borg/backup.env
chmod 600 ~/.config/borg/backup.env
nvim ~/.config/borg/backup.env
```

Store any identifying or machine-specific exclusion patterns in
`~/.config/borg/excludes.local`. Neither local file belongs in Git.
The script stays on the source filesystem by default, so mounted shares or
removable filesystems below the home directory are not copied accidentally.
Set `BORG_ONE_FILE_SYSTEM=0` only when those mounted trees are intentional
backup sources.

When free space falls below `BORG_MIN_FREE_GIB`, the script applies the normal
retention policy and compacts the repository before deciding whether there is
enough room to create another archive.

During recovery, set `BORG_PRUNE=0` to preserve an interrupted checkpoint
archive. This also pauses normal archive rotation; remove the override after
the checkpoint has been recovered or intentionally retired.

Test interactively before enabling the schedule:

```bash
systemctl --user start borg-backup.service
journalctl --user -u borg-backup.service -n 100 --no-pager
systemctl --user enable --now borg-backup.timer
```

After freeing space or recovering from an interrupted job, verify the
repository and stream a known small file from the newest archive before
trusting the schedule again:

```bash
set -a
source ~/.config/borg/backup.env
set +a
borg check --repository-only "$BORG_REPO"
borg list "$BORG_REPO"
borg extract --stdout "$BORG_REPO::ARCHIVE" path/to/a/small/file >/dev/null
```

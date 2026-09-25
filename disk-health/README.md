# Disk health guard

This package installs a lightweight user timer that checks the root filesystem
with `df` once per hour. It sends a desktop notification at 85% usage and a
critical notification at 90%, with reminders limited to once every 12 hours.
It also announces when usage returns below the warning threshold.

The guard never scans directory trees and never deletes files. Its small
notification state lives outside the repository under
`${XDG_STATE_HOME:-$HOME/.local/state}/disk-space-guard/`.

Install and enable it with:

```bash
./install.sh --dry-run disk-health
./install.sh disk-health
systemctl --user daemon-reload
systemctl --user enable --now disk-space-guard.timer
```

Run an immediate check with:

```bash
systemctl --user start disk-space-guard.service
journalctl --user -u disk-space-guard.service -n 20 --no-pager
```

Thresholds can be overridden in a systemd user-unit drop-in with
`DISK_SPACE_WARN_PERCENT`, `DISK_SPACE_CRITICAL_PERCENT`, and
`DISK_SPACE_REMINDER_SECONDS`.

Capacity monitoring complements the system SMART daemon and weekly SSD TRIM;
it does not replace them. On a new installation, verify SMART directly and
enable its privileged monitor separately:

```bash
sudo smartctl -H -A /dev/sdc
sudo systemctl enable --now smartd.service
```

Confirm the device name with `findmnt /` and `lsblk` before running the SMART
command. The default Arch `smartd.conf` uses `DEVICESCAN` to monitor detected
drives.

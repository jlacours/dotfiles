# Mako Notification Daemon (Retired)

> [!NOTE]
> Mako has been replaced by the native Quickshell notification daemon in `hyprbar` (`quickshell/.config/quickshell/hyprbar/Notifications*.qml`).

## Retirement & Cleanup Instructions

To completely retire and remove Mako from the system:

1. Unstow the Mako package from `~/.dotfiles`:
   ```bash
   stow -D -d ~/.dotfiles -t ~ mako
   ```

2. Uninstall the Mako binary and package via `yay`:
   ```bash
   yay -Rns mako
   ```

3. If desired, move the `mako/` folder into `legacy/` or remove it:
   ```bash
   mv ~/.dotfiles/mako ~/.dotfiles/legacy/
   ```

## Rollback Instructions (if reverting to Mako)

If you ever wish to re-enable Mako:

1. Re-enable the systemd user service:
   ```bash
   systemctl --user unmask mako.service
   ```

2. Restow Mako configuration:
   ```bash
   stow -R -d ~/.dotfiles -t ~ mako
   ```

3. Start Mako or allow D-Bus activation to start it:
   ```bash
   systemctl --user start mako.service
   ```

4. In `hyprland/.config/hypr/modules/keybinds.lua:71`, revert the dismiss command back to `"makoctl dismiss --all"`.

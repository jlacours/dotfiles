---
name: win95-desktop
description: Maintain and visually validate the Labwc and Quickshell Windows 95 desktop in the dotfiles repository. Use whenever work touches quickshell/.config/quickshell/win95, Labwc Win95 borders or themes, GTK/Qt Win95 application chrome, taskbar or Start-menu behavior, notifications, close/minimize/maximize controls, launchers and keybind surfaces, wallpaper, output geometry, or light/dark visual consistency.
---

# Maintain the Win95 Desktop

Keep the live Labwc session visually coherent and compositor-safe across
Quickshell, Labwc borders, GTK, and Qt.

## Required context

1. Resolve the dotfiles root and read the root and `quickshell/AGENTS.md` files.
2. Read [references/visual-contract.md](references/visual-contract.md) before
   changing UI geometry, colors, controls, focus behavior, or theme assets.
3. Confirm the live target before editing:

```bash
printf '%s\n' "$XDG_CURRENT_DESKTOP" "$XDG_SESSION_TYPE"
quickshell list --all
pgrep -af 'labwc|quickshell'
```

Only treat `quickshell/win95` as live when Quickshell reports its `shell.qml`.

## Workflow

1. Inspect the live component, its QML caller, and the corresponding Labwc or
   GTK theme asset. Do not infer behavior from filenames.
2. For visual work, inspect an actual Windows 95 reference image before choosing
   geometry. Preserve the interaction model as well as the palette: Programs is
   a Start-menu cascade; Find is a window; task controls are pixel glyphs.
3. Reuse the canonical source named in the visual contract. Do not approximate
   an existing pixel asset with a font glyph or create a second palette.
4. Keep the Win95 profile self-contained. The square Hyprland profile is useful
   reference material, not a runtime dependency. Share only explicitly
   compositor-neutral scripts or protocols.
5. Apply the change to the live session and inspect a screenshot on both
   monitors. A clean log alone is insufficient for user-visible work.
6. Update README or package notes when behavior, dependencies, keybinds, or the
   theme contract changes. Do not commit unless the user asks.

## Focus and popup safety

- Never dismiss a menu with a fullscreen transparent input surface.
- Prefer exact-size `PopupWindow` surfaces or a normal `FloatingWindow`.
- For native popup grabs, keep Escape and a finite timeout as escape routes.
- Test open and close through IPC with a cleanup trap before asking the user to
  risk their keyboard focus.
- If a grab blacks another output, traps focus, or behaves differently under
  Labwc, stop and use compositor events or a normal window instead of a
  Hyprland-specific focus-grab protocol.

## Validation

Regenerate the Win95 `qmldir` after adding or renaming QML types:

```bash
~/.config/quickshell/scripts/gen-qmldir.sh ~/.config/quickshell/win95
```

Restart and inspect the live shell:

```bash
~/.config/quickshell/scripts/qs-switch.sh restart
quickshell list --all
quickshell ipc --pid "$(pgrep -ox quickshell)" show
timeout 2 quickshell log --pid "$(pgrep -ox quickshell)"
```

For notification or mode-sensitive chrome, preserve the current mode, exercise
both variants, and restore it even if a check fails:

```bash
initial_mode="$(cat ~/.cache/wallust-current-mode 2>/dev/null || printf light)"
trap '~/.config/labwc/scripts/win95-mode.sh "$initial_mode" >/dev/null' EXIT
for mode in light dark; do
  ~/.config/labwc/scripts/win95-mode.sh "$mode"
  sleep 1
  notify-send -a 'Win95 visual check' -i dialog-information -t 15000 \
    'Notification chrome' "Checking the $mode close control"
  ~/.config/labwc/scripts/screenshot.sh full
done
```

Click the close control in at least one variant to confirm the handler dismisses
the notification. Inspect both screenshots; do not count successful capture as
visual verification.

The installed `/usr/bin/qmllint` currently belongs to Qt 5 and returns `255`
without useful diagnostics on this Qt 6 Quickshell config. Treat a clean hard
restart and live log as the authoritative QML smoke test until a Qt 6 linter is
installed.

Run checks proportional to the files changed:

```bash
xmllint --noout labwc/.config/labwc/rc.xml labwc/.config/labwc/menu.xml
bash -n labwc/.config/labwc/scripts/*.sh
./install.sh --dry-run labwc quickshell wallust
"$HOME/Projects/repos/jlacours-skills/manage-dotfiles/scripts/stow-check.sh" "$PWD"
git diff --check
```

For GTK theme edits, load both light and dark variants through
`gtk-query-settings` and `gtk4-query-settings` and reject parser warnings. End
substantial work with the full worktree audit from the manage-dotfiles skill.

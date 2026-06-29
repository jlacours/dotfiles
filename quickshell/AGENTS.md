# Quickshell Bar Notes

This package is a Stow package for the Quickshell bar config at:

- `quickshell/.config/quickshell`

## Project Direction

- This bar is replacing the old `eww` bar.
- Keep the Quickshell config modular.
- Do not collapse the bar into one giant QML file.
- Prefer small focused components and grouped subdirectories.

## Current Structure

- `shell.qml`: root entrypoint
- `Bar.qml`: top bar window composition
- `Workspace.qml` / `WorkspaceChip.qml`: Hyprland workspace module
- `Clock.qml`: centered clock chip
- `Date.qml`: right-side date
- `Tray.qml` / `TrayItem.qml`: systray
- `Vpn.qml`: bar VPN indicator
- `IdleInhibitor.qml`: bar idle inhibitor indicator
- `popup/`: popup shell and popup content modules

## Styling Rules

- Sharp corners only by default. Do not add rounded corners unless explicitly requested.
- Use `Theme.fontFamily` for bar text; it currently resolves to `Comic Code`.
- Use Wallust-generated colors from `wallust.js`.
- Prefer the base16-style palette keys exposed there:
  - `base00`: bar background
  - `base01`: lighter surface / outline color
  - `base03`: muted text / inactive indicators
  - `base05`: normal foreground
  - `base0D`: accent
- Current visual language:
  - clock: filled accent chip
  - vpn / idle: outlined chips
  - workspaces: outlined when inactive, accent-filled when focused/active

## Workspace Rules

- Show occupied workspaces and also the focused workspace when empty.
- Support special workspaces.
- `special:dropdown` displays as `=`.
- `special:magic` displays as `-`.
- `special:dropdown` should sort last.
- Other `special:*` workspaces should sort after normal workspaces.

## Popup Direction

- Popup opens from hovering the centered clock.
- Left click on the clock pins/unpins the popup.
- Popup should appear centered under the clock.
- Keep the popup modular:
  - `popup/PopupShell.qml`
  - `popup/BarPopup.qml`
  - `popup/QuickActions.qml`
  - `popup/WeatherCard.qml`
  - `popup/SystemColumn.qml`
  - supporting card/action modules
- The popup should preserve the old `eww` idea:
  - quick actions/status
  - weather hero card
  - compact system stats
- But it should be cleaner and more Quickshell-like than the old row-heavy `eww` panel.

## Performance Rules

- Prioritize low-overhead data sources.
- Reuse existing optimized scripts when they already exist.
- Prefer listener/socket-based sources over polling when practical.
- Only run expensive refreshes while the popup is visible.
- Current reused sources:
  - `waybar/scripts/expressvpn.sh`
  - `waybar/scripts/idle-inhibit.sh`
  - `eww/shell/bar_volume.sh`
  - `eww/shell/bar_language.sh`
  - `eww/shell/bar_weather.sh`
  - `eww/scripts/eww-bar` for one-shot system metrics

## Wallust

- Wallust template lives at:
  - `~/.config/wallust/templates/quickshell-colors.js`
- Wallust generates:
  - `~/.config/quickshell/wallust.js`
- Quickshell should consume `wallust.js` instead of hardcoded colors wherever practical.

## QML Language Server (qmlls) — cursed but it works

The bar runs fine, but `qmlls6` (the Qt6 QML language server) spams false
warnings on every singleton consumer:

- `Member "barHeight" not found on type "Theme"`
- `Type Theme not declared as singleton in qmldir but using pragma Singleton`

Cause: the config has many `pragma Singleton` files (`Theme.qml`, all the
`*State.qml`). Quickshell resolves these implicitly at runtime — **no `qmldir`
needed**. But `qmlls` refuses to resolve a singleton's *members* unless a real
`qmldir` in the *source* directory declares it `singleton`.

Quickshell's own `.qmlls.ini` tooling does **not** fix this on the current
toolchain (Quickshell 0.3.0 + Qt 6.11): it synthesizes the qmldirs into a VFS
using symlinks, but `qmlls` canonicalizes those symlinks back to the source dir
(which has no qmldir) and the fix is lost. So do not bother with `.qmlls.ini`.

The cursed-but-working solution: commit real, **complete** `qmldir` files in each
source directory. They are generated, never hand-edited.

### Workflow when coding

After adding, removing, or renaming any `*.qml` component, regenerate:

```bash
~/.config/quickshell/scripts/gen-qmldir.sh
```

Rules baked into the generator (don't fight them):

- Every directory with PascalCase `*.qml` gets a `qmldir`.
- Each component is listed (`Foo Foo.qml`); `pragma Singleton` files get the
  `singleton` prefix.
- **All** components are listed, not just singletons — once a `qmldir` exists the
  directory is a strict module, so a missing entry breaks bare-name references at
  runtime ("X is not a type").
- No `module` line, no version numbers (both verified unnecessary).

These `qmldir` files are LSP-only sugar; the running bar does not need them, and
Quickshell honors an explicit `qmldir` instead of synthesizing its own.

## Pending UX Note

- After popup work is stable, the date should get a visual pass so it matches the rest of the bar.

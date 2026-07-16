# Quickshell Bar Notes

This package is a Stow package for the Quickshell bar config at:

- `quickshell/.config/quickshell`

## Project Direction

- This bar is replacing the old `eww` bar.
- Keep the Quickshell config modular.
- Do not collapse the bar into one giant QML file.
- Prefer small focused components and grouped subdirectories.

## Variants

- **`square/` is the live Hyprland variant.** It is a self-contained config
  rooted at `~/.config/quickshell/square/` (its own `shell.qml`, `Theme.qml`,
  `qmldir`, and `wallust.js`).
- **`win95/` is the live Labwc variant.** It provides the teal desktop and
  selection marquee, bottom taskbar, grab-based Start popup,
  desktop-entry-aware task icons, tray, clock, and its own exact-size
  application/favorites/tools/power/dmenu popup. It adapts the square menu's
  useful state shape but does not import Hyprland-specific menu state. Its
  Programs cascade supports
  type-ahead selection, and its desktop root menu opens a dedicated Win95
  Display Properties wallpaper chooser rather than the shared dmenu surface.
- `scripts/launch.sh` runs either variant with `quickshell -p`; `qs-switch.sh`
  can restart the current session, switch explicitly, or toggle between them.
- **The classic variant is retired**, archived at `legacy/quickshell-classic/`
  (repo-root `legacy/`, which `install.sh` lists in `SKIP_DIRS` so it is never
  stowed). It is reference-only; do not wire anything into it. Before any bar
  work, confirm the live variant with `qs-switch.sh status` (or
  `pgrep -af quickshell`) and edit under `square/`.

## Current Structure (square/)

- `shell.qml`: root entrypoint (mounts the bar, OSD, notifications, panels).
- `Bar.qml`: top bar composition — left cluster (workspaces, then the
  center-module toggle glyphs via `CenterToggleBlock`), centre cluster which is
  **mode-switched**: shows the status group (AI usage / tmux / vitals) when
  `CenterModulesState.news` is false, or the `RssBlock` news ticker when true
  (the two are mutually exclusive — the ticker is too wide to share the
  center); right cluster (tray, notifications, keyboard, volume, clock)
  separated by hairline `Rectangle` dividers.
- `Theme.qml`: singleton with the design tokens (see Styling Rules).
- Components follow a `*Block.qml` (bar widget) + `*State.qml` (singleton
  backing logic) split — e.g. `GameModeBlock`/`GameModeState`,
  `NetSpeedBlock`/`NetSpeedState`, `VolumeBlock`/`VolumeState`.
- `Workspaces.qml`, `Clock.qml`, `TmuxSessions.qml`, `TrayBlock`/`TrayItem`,
  `Osd.qml`/`OsdState.qml`: standalone modules.
- Panels/popovers: `AiUsagePanel.qml`, `VolumeMenu.qml`, `NotificationCenter.qml`.
- News ticker: `RssBlock.qml` (center widget — ‹ › arrows + continuous
  scrolling marquee of all headlines joined into one string, click-to-open, hover
  to pause) + `RssState.qml` (singleton backing it), backed by `scripts/rss.sh`
  (feedparser + per-feed 900s cache → merged JSON array) and the stowable
  `rss-feeds.txt` feed list.
- `CenterModulesState.qml` also owns the center-mode flag `news`; toggling any
  status module sets `news=false` (leaves ticker mode), so the toggle glyphs
  double as mode switches. `CenterToggleBlock` groups the three status glyphs
  behind a hairline divider from the 4th (news) glyph.
- Notifications: `NotificationState`, `NotificationBlock`, `NotificationCenter`,
  `NotificationItem`, and `NotificationPopups`.
- `clipboard/`, `keybinds/`, `menus/`, `scripts/` are shared (symlinked into
  `square/`).
- `wallust.js` is the generated palette (see Wallust).

## Menus (rofi replacement)

- `menus/` is the quickshell replacement for the retired `rofi` package
  (now `legacy/rofi/`, unstowed — see `install.sh`'s `SKIP_DIRS`). Every
  former rofi menu (drun, favourites, tools, power, window switcher, and the
  dmenu-piped scripts) now goes through this module.
- `menus/MenuState.qml` (singleton): all data + logic — item list, filter,
  per-mode `show*()` populators (`showApps`, `showFavorites`, `showTools`,
  `showPower`, `showWindows`, `showDmenu`), and `activateCurrent()` /
  `cancelCurrent()` dispatch.
- `menus/CenterMenu.qml`: the visual overlay — `PanelWindow` + `Variants`
  over `Quickshell.screens` (same shape as `clipboard/ClipboardHistory.qml`),
  but **centered both axes** (`anchors.centerIn`) and wide
  (`~55% of screen width`, clamped 480–920px) instead of fullscreen — that's
  the whole point versus the old rofi theme (`juju-default.rasi`,
  `fullscreen: true`). Hosts the `menu` `IpcHandler` (`openApps`,
  `openFavorites`, `openTools`, `openPower`, `openWindows`, `openDmenu`,
  `hide`) — called via `scripts/qs-ipc.sh menu <function> ...` from
  `hyprland.conf` and from `scripts/qs-dmenu.sh`.
- `menus/MenuItem.qml`: list delegate (mirrors `clipboard/ClipboardItem.qml`).
- `scripts/qs-dmenu.sh`: dmenu-compatible CLI shim (stdin lines in → temp item
  file + chosen line on stdout via a one-shot FIFO) so the scripts that used to
  pipe into
  `rofi -dmenu` (`todo.sh`, `wallpaper.sh`, `emojis.sh`, `cliphist.sh`,
  `screenshot.sh`, `screenrecord.sh`, `deactivate-screens.sh`, `claude.sh`,
  `speak.sh`, `rofi-configs.py`) needed only a one-line substitution. It
  supports a deliberately small subset of rofi's dmenu flags — see the
  script's header comment.
- Text-only by design: app/window/favourite icons and the old
  wallpaper/cliphist image previews were dropped rather than ported, to keep
  this module's scope bounded. Revisit if the user wants icons back.

## Styling Rules (square)

- Brutalist: **zero radius everywhere** (`Theme.radius === 0`). Do not add
  rounded corners unless explicitly requested.
- Consume colors via `Theme` semantic tokens, not raw palette keys:
  - `Theme.bg` (bar background), `Theme.surface`, `Theme.border`,
    `Theme.foreground`, `Theme.text`, `Theme.textMuted`, `Theme.textDim`
  - `Theme.accent` / `Theme.accentAlt`, plus status colours
    `Theme.critical` / `Theme.success` / `Theme.warning` / `Theme.info`
  - (`wallust.js` still derives these from its base16 vars underneath, but bar
    code should go through `Theme`.)
- Typography: `Theme.fontFamily` ("Comic Code") for text, `Theme.iconFamily`
  ("Symbols Nerd Font Mono") for glyphs; sizes are `Theme.fontSm` / `fontMd` /
  `fontLg` (10 / 11 / 13).
- Geometry tokens: `Theme.hairline` (1px) for dividers, `Theme.stripe` (2px),
  `Theme.barHeight` (28), spacing `padXs/padSm/padMd/padLg`, `gapLg`.
- Airy presentation tokens keep the square geometry while softening its mass:
  `Theme.barSurface`, `panelSurface`, `cardSurface`, `controlSurface`, and
  `borderSubtle`. Base semantic colors remain opaque for text and active states.
- Right-cluster neighbours are separated by a short, subdued hairline
  (`Theme.hairline` × `Theme.dividerHeight`, colored `Theme.borderSubtle`).
- Visual language: values in fixed-width slots so they never nudge neighbours;
  accent colour = active/on, `textDim` = inactive/off, `critical` = fault.

## Workspace Rules

- Show occupied workspaces and also the focused workspace when empty.
- Support special workspaces.
- `special:dropdown` displays as `=`.
- `special:magic` displays as `-`.
- `special:dropdown` should sort last.
- Other `special:*` workspaces should sort after normal workspaces.

## Popup Direction

> Note: this section documents the **archived classic** `popup/` module (now in
> `legacy/quickshell-classic/popup/`). The live `square/` variant has no
> `popup/` tree; its equivalent surfaces are `AiUsagePanel.qml`,
> `VolumeMenu.qml`, and `NotificationCenter.qml`. Keep these notes only as
> historical intent for any future square popup work.

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

## Labwc Start Menu Dismissal (recurring)

`win95/StartMenu.qml` is an anchored `PopupWindow` with a compositor-native
grab. A previous attempt at this shape failed on the same stack (Quickshell
0.3.0, Qt Wayland 6.11, Labwc 0.20: the surface stayed mapped after outside
clicks with no fresh warnings), which forced a detour through an exact-size
`FloatingWindow` plus per-output Labwc title rules, activation tracking, and a
safety timer. The grab-based popup now dismisses correctly — the difference is
implementation details, not compositor versions, so keep every load-bearing
piece below when touching this file:

- `anchor.window: barWindow` parents the popup to the taskbar surface of its
  own output, with the anchor rect at the bar's top-left and
  `Edges.Top | Edges.Right` gravity opening it upward. A popup without a real
  transient parent is exactly the shape that used to stay mapped.
- `grabFocus: true` requests the explicit xdg_popup grab; the compositor then
  dismisses on outside clicks, including clicks on other outputs.
- `onVisibleChanged` folds compositor-side dismissal back into the `open`
  property. Without it the QML state desyncs and the next toggle no-ops.
- The surface is a fixed-size transparent canvas sized for the full Programs
  cascade; panels draw inside it and never resize the mapped surface.
  Transparent regions of a Wayland surface still receive input, so the
  background `MouseArea` closes the menu when a click lands on the canvas
  outside a panel. This is not a fullscreen click catcher — the canvas never
  exceeds the menu footprint.
- Each per-output bar instantiates its own `StartMenu`; the scope coordinator
  tracks `activeMenu` and `isOwner` gates which instance draws its panels.
- Task buttons, tray icons, and the Quickshell desktop surface still emit
  `Win95MenuState.closeStartRequested` so presses they consume also close the
  menu. The `startmenu.hide` IPC performs the same close for scripts.
- Escape remains as the safety exit if the compositor ever fails the grab.

The retired `FloatingWindow` machinery left per-output
`juju95-start-menu-*` `windowRule` entries in Labwc's `rc.xml`; they match
nothing now and can be dropped whenever that file is next touched.

Two diagnostics are easy to misread:

- `Failed to create grabbing popup` is emitted by Qt Wayland when the popup has
  no transient parent **or** `lastInputDevice()` is absent. A throwaway uinput
  device that is destroyed immediately after clicking can create this failure
  artificially; keep the same virtual input device alive through the entire
  open/click-away sequence.
- `log.qslog` is binary. Read the timestamped text in the instance's `log.log`
  or use `quickshell log`; old warnings are not evidence of a new failure.

Regression test matrix:

1. Start alone closes from an outside click on the same output.
2. Programs and Settings close from an outside click.
3. The transparent L-shaped area above the main menu closes Programs.
4. A click on another output closes the menu.
5. Escape closes immediately.
6. With Programs open, typing `fo` selects Foot and Enter launches exactly one
   new Foot process. Record existing PIDs first and terminate only the test PID.

## Performance Rules

- Prioritize low-overhead data sources.
- Reuse existing optimized scripts when they already exist.
- Prefer listener/socket-based sources over polling when practical.
- Only run expensive refreshes while a panel is visible.
- `square/` ships its own helpers via the shared `scripts/` dir (symlinked in
  as `square/scripts/`) — e.g. `ai-usage.sh`, `network-status.sh`,
  `audio-rate.sh`, `game-mode` via `~/.config/hypr/scripts/game-mode.sh`.
  (The old `waybar/` and `eww/` script paths below are legacy references from
  the pre-square era; prefer the in-tree `scripts/` helpers for new modules.)

## Wallust

- Wallust template lives at:
  - `~/.config/wallust/templates/quickshell-colors.js`
- Wallust generates the palette consumed by the live variant:
  - `~/.config/quickshell/square/wallust.js` (imported by `square/Theme.qml`)
  - (a top-level `~/.config/quickshell/wallust.js` also exists; it is leftover
    from the retired classic variant and is not consumed by `square/`.)
- Quickshell should consume `wallust.js` via `Theme` tokens, not hardcoded colors.

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

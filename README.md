# Dotfiles

Personal Arch Linux dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Install

Install the repository prerequisites:

```bash
yay -S --needed git stow gitleaks
git clone https://github.com/jlacours/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh --dry-run
./install.sh
```

Install the Zsh completion dependencies:

```bash
yay -S --needed zsh zsh-completions fzf carapace-bin
```

Install local network diagnostic tools:

```bash
yay -S --needed nmap
```

Install a subset by naming packages:

```bash
./install.sh zsh foot qtile quickshell
```

`install.sh` only manages symlinks. Applications and feature dependencies remain explicit so the script does not turn into a surprise package-manager séance.

The Labwc session has been retired and archived to `legacy/labwc/`. The active qtile and Quickshell setup expects:

```bash
yay -S --needed qtile qtile-extras python-pywlroots hypridle wlopm wlr-randr xorg-xrandr rofi mako swaybg quickshell foot wallust libnotify grim slurp wl-clipboard wtype cliphist network-manager-applet polkit-kde-agent papirus-icon-theme ranger pcmanfm pulsemixer pavucontrol playerctl xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
```

The optional Hyprland session expects:

```bash
yay -S --needed hyprland hypridle quickshell foot filezilla jq pipewire-pulse libnotify polkit wallust wl-clipboard ffmpeg grim slurp wf-recorder xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland zen-browser-bin
```

The `mako` package is the qtile session's notification daemon (launched from
qtile's autostart); the Quickshell win95 profile still owns its own
notification server when it is running.

qtile uses its own compositor-safe `hypridle` configuration: after 15 minutes
of uninhibited idle time, `wlopm` powers off both monitors and restores them on
input. It does not lock or suspend the session. A keep-awake toggle sits in the
taskbar tray left of the clock: a small CRT chip that latches sunken and lights
its screen while it holds a `zwp_idle_inhibit` lock (via the shared
`idle-inhibit.sh` helper), parking the monitor timeout until toggled off.

The same tray includes a live PipeWire volume readout. Scroll it for 5% volume
steps, left-click to mute, or right-click to open `pavucontrol`.

qtile's Win95 Quickshell profile owns its notification server and renders native
Win95-styled popups without a second daemon. `Print` saves a focused-monitor PNG
under `~/Pictures` and copies it to the clipboard, while `Shift+Print` does the
same for a selected region. `Ctrl+Print` selects a region for the clipboard
without keeping a file. Each completed action shows a visible confirmation.

The same profile provides native Quickshell launchers rather than Rofi or a
fullscreen click-catching layer. `Super+D` opens the authentic Start → Programs
cascade on the active window's monitor. Its type-ahead selection accepts program
initials or longer prefixes, and Enter launches the highlighted application.
Start → Find and `Super+F3` open a separate Win95-style application search
window. `Super+B`, `Super+S`, and `Super+Shift+Q` open favorites, tools, and
power. `Super+V` routes clipboard history through the Win95 dmenu-compatible
popup, while `Super+F1` shows the active qtile bindings. The Start menu is a
popup anchored to the taskbar with a compositor-native grab, so clicking
anywhere outside dismisses it; Escape is retained as a safety exit.

The desktop right-click menu opens a Win95-style Display Properties wallpaper
chooser backed by `~/Pictures/Wallpapers`, with a monitor preview, placement
controls, and classic OK/Cancel/Apply actions. qtile stores its selected image
and placement under `~/.local/state/quickshell/win95-wallpaper*`; the Win95
desktop renders it directly while preserving teal as the solid-color fallback.

Quickshell also ships matching `win95-light` and `win95-dark` GTK3/GTK4 themes. The
active session's environment gives Qt applications the built-in square Windows
control style and the GTK palette, so application chrome follows the same
classic bevels without leaking Win95 theme variables into Hyprland. The mode
switcher changes a runtime `win95-current` symlink and never rewrites tracked
configuration; existing Qt applications need reopening after a mode change,
and a fresh login applies the complete environment.

Portal selection is desktop-specific. Hyprland and qtile provide separate
`*-portals.conf` files, selected through `XDG_CURRENT_DESKTOP`; there is no
generic `portals.conf` that could force one compositor's capture backend into
the other session. Neutral application defaults remain shared in the
`environment` package. A shared display-service reset helper clears stale portal
and polkit processes when the persistent systemd user manager survives a
compositor switch—it does not set compositor identity or hardcode a numbered
Wayland socket.

The interface font is `Comic Code`. It is a commercial typeface not packaged on the AUR, so install it manually into `~/.local/share/fonts/`.

### Companion tools

Desktop helpers and the local-model launcher are maintained separately and install stable executables into `~/.local/bin`:

```bash
mkdir -p ~/Projects/repos
git clone https://github.com/jlacours/jlacours-tools.git ~/Projects/repos/jlacours-tools
git clone https://github.com/jlacours/llama-choose.git ~/Projects/repos/llama-choose
~/Projects/repos/jlacours-tools/install.sh
~/Projects/repos/llama-choose/install.sh
```

CLIProxyAPI exposes Claude and Codex subscription OAuth sessions through a
loopback-only Anthropic-compatible endpoint. Install its AUR package, create
`~/.cli-proxy-api/config.yaml` and `client-token` as machine-local
credentials, then authenticate and enable its user service:

```bash
yay -S --needed cli-proxy-api-bin
cli-proxy-api -config ~/.cli-proxy-api/config.yaml -claude-login
cli-proxy-api -config ~/.cli-proxy-api/config.yaml -codex-login
systemctl --user enable --now cli-proxy-api.service
```

The `claudex` Zsh function launches Claude Code through that gateway while
ordinary `claude` continues to use its native configuration.

Game mode can switch the CPU governor without prompting after installing its narrow sudo helper:

```bash
sudo ~/.config/hypr/scripts/install-game-mode-governor.sh
```

Review `MANAGED_UNITS` in `hyprland/.config/hypr/scripts/game-mode.sh` first; those user services are paused while game mode is active.

hypridle runs with `ignore_dbus_inhibit = true`, so it ignores the browser's audio/video idle locks. A `hypridle-video-inhibit.service` user unit restores "stay awake while watching" by holding a `systemd-inhibit --what=idle` lock only while a window is fullscreen; audio-only playback still idles out. Stow only links the unit, so enable it once:

```bash
systemctl --user enable --now hypridle-video-inhibit.service
```

## Stow Packages

Every application follows the same template: a top-level package mirrors its destination relative to `$HOME`.

| Package | Software and purpose |
|---|---|
| **emacs** | Emacs daemon/client configuration with pixel-precise GUI resizing, Gruber Darker, and local LLM chat with an activity spinner, auto-scroll, native code highlighting, and hidden reasoning output; the default editor |
| **environment** | compositor-neutral systemd user environment.d variables, desktop MIME defaults, and portal session cleanup |
| **eww** | Legacy Eww bar retained for migration reference |
| **foot** | Foot terminal — the default terminal across qtile and Quickshell scripts; Wallust color include |
| **hyprland** | Hyprland, hypridle (with a fullscreen-aware idle inhibitor), keybindings, game mode, and compositor helpers |
| **mako** | Win95-styled notification daemon; launched by the qtile session (the Quickshell win95 profile uses its own notification server instead) |
| **nvim** | Neovim configuration, plugins, mappings, and the Darklime theme; available as the secondary editor |
| **qtile** | Active tiling Wayland session: Hyprland-style keybinds ported to qtile, Rofi-based menus (drun, apps, tools, power, clipboard history, keybind viewer), mako notifications, scratchpad dropdowns, hypridle monitor idling, and a wlr xdg-desktop-portal config |
| **quickshell** | Win95 desktop, taskbar, and Start menu for the active qtile session, plus an optional Hyprland bar profile |
| **sway** | Legacy Sway configuration |
| **tmux** | tmux terminal multiplexer configuration |
| **wallust** | Wallust color-generation configuration |
| **zsh** | zsh shell configuration, prompt schema, native completion, and Carapace coverage for unsupported commands |

Repository-only directories such as `scripts/`, `assets/`, `legacy/`, and `.agents/` are not Stow packages.

## Current Desktop

The active desktop is qtile (the Labwc session was retired and archived to
`legacy/labwc/`). It uses Win95 window chrome,
a Quickshell desktop with a classic left-drag selection marquee, a taskbar with
desktop-entry-aware application icons, an exact-size Start menu, and Foot. The
desktop root menu opens only on right-click and includes persistent wallpaper
selection.
Dark mode switches the complete chrome palette and desktop fallback color;
light mode keeps the classic teal fallback. The Win95 Quickshell profile owns its own
application/favorites/tools/power,
clipboard, dmenu, and keybinding surfaces; qtile separately provides Rofi-based
menus (drun launcher, apps, tools, power, clipboard history, and a keybind
viewer) for its own session-level bindings. The optional square profile remains isolated for an
explicitly selected Hyprland session and is not current-session truth.

Zen Browser is the default browser. Default programs are centralized in the
`environment` package: session variables live in `.config/environment.d/`, and
desktop file associations live in `.config/mimeapps.list`. The interface font
is `Comic Code` across Quickshell, Foot, Emacs, and qtile.

The Quickshell config ships generated `qmldir` files (via
`quickshell/.config/quickshell/scripts/gen-qmldir.sh`) purely to keep the QML
language server quiet. Quickshell resolves its `pragma Singleton` modules
implicitly at runtime, but `qmlls` refuses to resolve singleton members without a
real `qmldir` in the source tree — and Quickshell's own `.qmlls.ini` tooling does
not help, because `qmlls` canonicalizes its VFS symlinks back to the source. The
fix is therefore a cursed-but-working pile of generated `qmldir` files; regenerate
them after adding or renaming components. See [`quickshell/AGENTS.md`](quickshell/AGENTS.md).

The editor configuration is Emacs-first, running as a user daemon with
`emacsclient`. Neovim remains configured and available as the secondary editor.

## Repository Automation

[`AGENTS.md`](AGENTS.md) explains the repository layout and safety rules for coding agents browsing the project on GitHub.

The project-local `$commit-dotfiles` skill lives at `.agents/skills/commit-dotfiles/`. It reviews the complete worktree, checks sensitive information and line endings, verifies Stow layout and documentation, runs relevant validation, and commits the intended snapshot. The auto-discovered `$win95-desktop` skill at `.agents/skills/win95-desktop/` carries the Quickshell visual contract, canonical control assets, compositor-separation rules, focus-safety constraints, and live screenshot workflow for future Win95 changes.

See [CHANGELOG.md](CHANGELOG.md) for historical release notes.

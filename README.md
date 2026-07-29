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

Install Herdr, the terminal multiplexer used by this configuration:

```bash
curl -fsSL https://herdr.dev/install.sh | sh
```

The Herdr Zsh completion is vendored at `zsh/.zfunc/_herdr` and stowed into
`~/.zfunc`, which is already on `fpath`. Regenerate it after a Herdr upgrade:

```bash
herdr completion zsh > ~/.dotfiles/zsh/.zfunc/_herdr
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
```

Install local network diagnostic tools:

```bash
yay -S --needed nmap
```

Install Borg when using the user-level backup package:

```bash
yay -S --needed borg
```

The tracked Borg script, exclusion rules, and systemd user units contain no
repository location or credentials. Copy
`~/.config/borg/backup.env.example` to `~/.config/borg/backup.env`, keep that
machine-local file out of Git, test the service once, and only then enable the
timer. See `borg/README.md` for the setup and restore-check commands.

Install a subset by naming packages:

```bash
./install.sh zsh foot qtile
```

`install.sh` only manages symlinks. Applications and feature dependencies remain explicit so the script does not turn into a surprise package-manager séance.

The Labwc and full Quickshell desktops have been retired and archived under
`legacy/`. A minimal Quickshell bar remains available for Hyprland. The active
qtile setup expects:

```bash
yay -S --needed qtile qtile-extras python-pywlroots hypridle wlopm wlr-randr xorg-xrandr fuzzel mako swaybg foot wallust libnotify grim slurp wl-clipboard wtype cliphist tesseract wf-recorder network-manager-applet polkit-kde-agent papirus-icon-theme ranger pcmanfm pulsemixer pavucontrol xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
```

The optional Hyprland session expects:

```bash
yay -S --needed hyprland hypridle quickshell fuzzel foot filezilla jq pipewire-pulse libnotify polkit wallust wl-clipboard ffmpeg grim slurp wf-recorder cliphist tesseract xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland zen-browser-bin
```

Hyprland uses Fuzzel for its application, favorites, tools, window, power,
clipboard-history, keybinding, and screen-management menus. The tools menu
also covers screen recording, an emoji/Unicode picker, OCR, and a wallpaper
picker.

The minimal Hyprland bar watches Wallust's generated palette, so
`wallust theme <name>` updates its background, text, hover, border, and accent
colors without restarting Quickshell.

The `mako` package is qtile's notification daemon, launched from qtile's
autostart.

qtile uses its own compositor-safe `hypridle` configuration: after 15 minutes
of uninhibited idle time, `wlopm` powers off both monitors and restores them on
input. It does not lock or suspend the session.

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
| **borg** | Portable, user-level encrypted backups with a daily systemd timer, cache-aware and filesystem-boundary exclusions, low-space retention recovery, and machine-local credentials/settings |
| **emacs** | Emacs daemon/client configuration with pixel-precise GUI resizing, Gruber Darker, and local LLM chat with an activity spinner, auto-scroll, native code highlighting, and hidden reasoning output; available as the secondary editor |
| **environment** | compositor-neutral systemd user environment.d variables, desktop MIME defaults, and portal session cleanup |
| **eww** | Legacy Eww bar retained for migration reference |
| **foot** | Foot terminal — the default terminal across qtile; Wallust color include |
| **fuzzel** | Fast native Wayland application launcher and dmenu-compatible picker with a compact square theme |
| **hyprland** | Hyprland, hypridle (with a fullscreen-aware idle inhibitor), keybindings, game mode, and compositor helpers |
| **mako** | Notification daemon launched by the qtile session |
| **nvim** | Neovim configuration, plugins, mappings, and the Darklime theme; the default editor |
| **qtile** | Active tiling Wayland session: Hyprland-style keybinds ported to qtile, Fuzzel-based menus (applications, tools, power, clipboard history, keybind viewer, screen recording, emoji/Unicode picker, OCR, wallpaper picker), mako notifications, scratchpad dropdowns, hypridle monitor idling, and a wlr xdg-desktop-portal config |
| **quickshell** | Minimal multi-monitor Hyprland bar with Wallust-reactive colors, workspaces, active-window title, aligned system-tray menus, monitor name, and clock |
| **sway** | Legacy Sway configuration |
| **herdr** | Herdr terminal-native agent multiplexer configuration |
| **wallust** | Wallust color-generation configuration, application templates, and live desktop refresh hook |
| **zsh** | zsh shell configuration, prompt schema, native completion, and Carapace coverage for unsupported commands |

Repository-only directories such as `scripts/`, `assets/`, `legacy/`, and `.agents/` are not Stow packages.

## Current Desktop

The active desktop is qtile. It provides Hyprland-style keybinds, Fuzzel-based
menus (drun, apps, tools, power, clipboard history, and a keybind viewer), mako
notifications, scratchpad dropdowns, and Foot. The tools menu also covers
screen recording, an emoji/Unicode picker, OCR, and a wallpaper picker.

The minimal Qtile bar reads its palette from Wallust's generated `colors.py`.
Image palettes and the random light/dark theme helpers refresh the running
desktop automatically after Wallust rewrites its theme files.

Zen Browser is the default browser. Default programs are centralized in the
`environment` package: session variables live in `.config/environment.d/`, and
desktop file associations live in `.config/mimeapps.list`. The interface font
is `Comic Code` across Foot, Emacs, and qtile.

The editor configuration is Neovim-first. Emacs remains configured and
available as the secondary editor.

## Repository Automation

[`AGENTS.md`](AGENTS.md) explains the repository layout and safety rules for coding agents browsing the project on GitHub.

The project-local `$commit-dotfiles` skill lives at `.agents/skills/commit-dotfiles/`. It reviews the complete worktree, checks sensitive information and line endings, verifies Stow layout and documentation, runs relevant validation, and commits the intended snapshot.

See [CHANGELOG.md](CHANGELOG.md) for historical release notes.

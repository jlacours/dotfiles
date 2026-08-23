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

Install the Bitwarden CLI session wrapper to cache only the temporary vault
session in GNOME Keyring (never the master password):

```bash
yay -S --needed bitwarden-cli gnome-keyring libsecret
./install.sh --dry-run bitwarden
./install.sh bitwarden
bw unlock
```

See [`bitwarden/README.md`](bitwarden/README.md) for behavior, requirements, and
the `/usr/bin/bw` troubleshooting bypass.

Install the Boxcare fleet-maintenance runtime, then Stow its command and safe
logical inventory:

```bash
yay -S --needed python openssh
./install.sh --dry-run boxcare
./install.sh boxcare
```

`boxcare` audits by default; package changes require `boxcare update`, with
`boxcare update --dry-run` available to inspect the command plan first. Host
addresses and credentials remain in the local SSH configuration. See
[`boxcare/README.md`](boxcare/README.md) for selection, output, sudo, strict
host-key, and package-manager boundaries.

Install Borg when using the user-level backup package:

```bash
yay -S --needed borg
```

The tracked Borg script, exclusion rules, and systemd user units contain no
repository location or credentials. Copy
`~/.config/borg/backup.env.example` to `~/.config/borg/backup.env`, keep that
machine-local file out of Git, test the service once, and only then enable the
timer. See `borg/README.md` for the setup and restore-check commands.

Install Codex with the official standalone installer before enabling the
tracked Remote Control service:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
systemctl --user enable --now codex-remote-control.service
```

The service starts the official Codex-managed app-server daemon whenever the
user systemd manager starts. On an always-on host, enable lingering once so the
user manager starts at boot without waiting for an interactive login:

```bash
sudo loginctl enable-linger "$USER"
```

The `codex` package also overrides the ChatGPT desktop launcher to use
Electron's native Wayland backend instead of XWayland. After installing the
OpenAI ChatGPT desktop app, Stow the package and refresh the desktop database:

```bash
./install.sh codex
update-desktop-database ~/.local/share/applications
```

Fully quit and reopen ChatGPT after installing the override. Native Wayland
windows use the lowercase `chatgpt` app ID when matching compositor rules. The
Hyprland package excludes only the floating Codex pet from compositor blur,
leaving the application's own glass styling intact.

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

Active Wayland launchers use Foot's socket-activated server mode for lower
startup overhead and shared font/glyph caches. Enable the packaged user socket
once after installing Foot:

```bash
systemctl --user enable --now foot-server.socket
```

`footclient` starts the server on demand through that socket. The server reads
`foot.ini` when it starts, so restart `foot-server.service` only when no
terminal windows need to remain open after changing Foot configuration or
generated colors.

The optional Hyprland session expects:

```bash
yay -S --needed hyprland hypridle hyprpaper quickshell fuzzel foot filezilla jq pipewire-pulse libnotify polkit wallust adw-gtk-theme wl-clipboard ffmpeg grim slurp wf-recorder cliphist tesseract xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland librewolf helium-browser-bin
```

Hyprland loads `~/.config/hypr/hyprland.lua` as its live provider, with
monitors, workspaces, keybindings, and rules split into Lua modules. The
adjacent `hyprland.conf` remains synchronized as a rollback and monitor-layout
reference for session helpers.

Hyprland uses Fuzzel for its application, favorites, tools, window, power,
clipboard-history, keybinding, and screen-management menus. The tools menu
also covers screen recording, an emoji/Unicode picker, OCR, and a wallpaper
picker with cached thumbnail previews that can either regenerate the Wallust
theme or keep the current palette.

The minimal Hyprland bar watches Wallust's generated palette, so
`wallust theme <name>` updates its background, text, hover, border, and accent
colors without restarting Quickshell.

The bar also includes an ExpressVPN status chip when the ExpressVPN 5 client is
installed and activated. The chip polls `/usr/local/bin/expressvpnctl`, uses the
accent color while connected, and connects to the saved location or disconnects
on click without changing the selected region, protocol, or Network Lock.

The bar also includes a CPU governor chip beside the game-mode and VPN controls,
and the Mod+S tools menu exposes the same switch. Both show the live
`performance`/`powersave` state and use the same narrow helper installed for
game mode.

The Hyprpaper slideshow alternates the night-garden and dawn-after-rain 4K
wallpapers every 30 minutes without invoking Wallust, so wallpaper rotation
cannot change the calibrated palette. Enable its timer once after Stowing the
Hyprland package:

```bash
systemctl --user enable --now hyprpaper-slideshow.timer
```

Wallust's desktop hook pulses the maintained `adw-gtk3-dark` base theme after
regenerating GTK CSS, which hot-reloads native dialogs in already-running apps.
The calibrated desktop palette can be restored independently with
`wallust theme Tokyo-Night --skip-sequences`.

Enable the generated-file watcher once after Stowing the Wallust package:

```bash
systemctl --user enable --now wallust-refresh-desktop.path
```

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

Game mode is available from the controller chip in the Hyprland bar or with
`Super+Alt+G`. It pauses configured nonessential user services, enables Mako
do-not-disturb, disables compositor effects and idle handling, and can switch
the CPU governor without prompting after installing its narrow sudo helper:

```bash
sudo ~/.config/hypr/scripts/install-game-mode-governor.sh
```

Review `MANAGED_UNITS` in `hyprland/.config/hypr/scripts/game-mode.sh` first; those user services are paused while game mode is active.

Away mode prepares the workstation for an unattended but remotely reachable
period. It refuses to activate unless Tailscale, SSH, Codex Remote Control, and
systemd user lingering are healthy; then it records and pauses expendable user
services and desktop applications, preserves the current OpenRGB profile,
disables automatic suspend, locks the session, and powers off RGB and displays.
Networking, Codex Remote Control, the Hermes/Signal fallback, CLIProxyAPI, and
the Borg backup timer remain active.

```bash
yay -S --needed openrgb openssh tailscale
~/.config/hypr/scripts/away-mode.sh verify
~/.config/hypr/scripts/away-mode.sh on
~/.config/hypr/scripts/away-mode.sh status
~/.config/hypr/scripts/away-mode.sh off
```

Activation and restoration are idempotent. Restoration starts only the units
and desktop processes recorded as running when the mode was enabled, restores
the saved RGB profile, turns the displays back on, and deliberately leaves the
session locked for normal authentication.

hypridle runs with `ignore_dbus_inhibit = true`, so it ignores the browser's audio/video idle locks. A `hypridle-video-inhibit.service` user unit restores "stay awake while watching" by holding a `systemd-inhibit --what=idle` lock only while a window is fullscreen; audio-only playback still idles out. Stow only links the unit, so enable it once:

```bash
systemctl --user enable --now hypridle-video-inhibit.service
```

## Stow Packages

Every application follows the same template: a top-level package mirrors its destination relative to `$HOME`.

| Package | Software and purpose |
|---|---|
| **borg** | Portable, user-level encrypted backups with a daily systemd timer, cache-aware and filesystem-boundary exclusions, low-space retention recovery, and machine-local credentials/settings |
| **boxcare** | Bounded multi-host security/maintenance audits and explicit serialized updates, using a secret-free logical inventory and strict SSH behavior |
| **codex** | Codex Remote Control systemd user service plus a native-Wayland ChatGPT desktop launcher override |
| **emacs** | Emacs daemon/client configuration with pixel-precise GUI resizing, Gruber Darker, and local LLM chat with an activity spinner, auto-scroll, native code highlighting, and hidden reasoning output; available as the secondary editor |
| **environment** | compositor-neutral systemd user environment.d variables, desktop MIME defaults, and portal session cleanup |
| **eww** | Legacy Eww bar retained for migration reference |
| **foot** | Foot terminal with socket-activated server/client launches; Wallust color include |
| **fuzzel** | Fast native Wayland application launcher and dmenu-compatible picker with a compact square theme |
| **hyprland** | Hyprland, Hyprpaper (with a two-image 30-minute slideshow), hypridle (with a fullscreen-aware idle inhibitor), keybindings, game and remotely reachable away modes, and compositor helpers |
| **mako** | Notification daemon launched by the qtile session |
| **nvim** | Neovim configuration, plugins, mappings, and the Darklime theme; the default editor |
| **qtile** | Active tiling Wayland session: Hyprland-style keybinds ported to qtile, Fuzzel-based menus (applications, tools, power, clipboard history, keybind viewer, screen recording, emoji/Unicode picker, OCR, wallpaper picker), mako notifications, scratchpad dropdowns, hypridle monitor idling, and a wlr xdg-desktop-portal config |
| **quickshell** | Minimal multi-monitor Hyprland bar with Wallust-reactive colors, the full workspace set with per-monitor active state and edge placement, active-window title, aligned system-tray menus, monitor name, and clock |
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

LibreWolf is the default browser, with Helium retained as the alternate
Chromium-based browser. Default programs are centralized in the
`environment` package: session variables live in `.config/environment.d/`, and
desktop file associations live in `.config/mimeapps.list`. The interface font
is `Comic Code` across Foot, Emacs, and qtile.

The editor configuration is Neovim-first. Emacs remains configured and
available as the secondary editor.

## Repository Automation

[`AGENTS.md`](AGENTS.md) explains the repository layout and safety rules for coding agents browsing the project on GitHub.

The project-local `$commit-dotfiles` skill lives at `.agents/skills/commit-dotfiles/`. It reviews the complete worktree, checks sensitive information and line endings, verifies Stow layout and documentation, runs relevant validation, and commits the intended snapshot.

See [CHANGELOG.md](CHANGELOG.md) for historical release notes.

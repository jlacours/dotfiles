# Dotfiles

Personal Arch Linux dotfiles, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Install

Install the repository prerequisites:

```bash
sudo pacman -S --needed git stow gitleaks
git clone https://github.com/jlacours/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh --dry-run
./install.sh
```

The installer never overwrites regular files already in `$HOME`. If the dry
run reports a conflict, back up or move that exact file yourself and rerun the
dry run before installing; do not use `--adopt` without reviewing the result.

This setup does not use the AUR or an AUR helper. Software unavailable in the
official Arch repositories is built from audited upstream releases by the
companion `~/Projects/repos/juju-packages` project and published to its signed,
machine-local `[juju-local]` repository. Because that repository is configured
after the official repositories, official Arch packages always take
precedence. Normal installs and upgrades then stay on the standard
`pacman -S`/`pacman -Syu` path.

Install the Zsh completion dependencies:

```bash
sudo pacman -S --needed zsh zsh-completions fzf carapace-bin
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
sudo pacman -S --needed nmap
```

Install the Bitwarden CLI session wrapper to cache only the temporary vault
session in GNOME Keyring (never the master password):

```bash
sudo pacman -S --needed bitwarden-cli gnome-keyring libsecret
./install.sh --dry-run bitwarden
./install.sh bitwarden
bw unlock
```

See [`bitwarden/README.md`](bitwarden/README.md) for behavior, requirements, and
the `/usr/bin/bw` troubleshooting bypass.

Install the Boxcare fleet-maintenance runtime, then Stow its command and safe
logical inventory:

```bash
sudo pacman -S --needed python openssh
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
sudo pacman -S --needed borg
```

The tracked Borg script, exclusion rules, and systemd user units contain no
repository location or credentials. Copy
`~/.config/borg/backup.env.example` to `~/.config/borg/backup.env`, keep that
machine-local file out of Git, test the service once, and only then enable the
timer. See `borg/README.md` for the setup and restore-check commands.

Install the lightweight root-filesystem space guard and enable its hourly user
timer:

```bash
./install.sh --dry-run disk-health
./install.sh disk-health
systemctl --user daemon-reload
systemctl --user enable --now disk-space-guard.timer
```

It warns at 85% usage, becomes critical at 90%, rate-limits repeated desktop
notifications, and never scans directories or deletes files automatically. See
`disk-health/README.md` for manual checks and threshold overrides.

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

The `codex` package keeps the ChatGPT desktop launcher on the application's
default XWayland backend. Native Wayland is experimental for floating windows
and can misplace the pet overlay. After installing the OpenAI ChatGPT desktop
app, Stow the package and refresh the desktop database:

```bash
./install.sh codex
update-desktop-database ~/.local/share/applications
```

Fully quit and reopen ChatGPT after changing the launcher. Hyprland keeps the
floating ChatGPT pet overlay free of compositor blur,
border, and shadow while leaving the application's own styling intact.

The `mcp-services` package provides local-only HTTP/SSE wrappers for the memory,
time, and Exa web-search MCP servers, plus switchable local Laya/OpenRouter Jev
judgment wrappers and an optional dormant Friend bridge. Exa's API key stays in
the machine-local `~/.zshenv.local`; the service passes only that variable to
the pinned Exa server process. The wrappers bind
only to `127.0.0.1`, which is the exposure boundary. The user units also request
Tailscale-range filtering with `IPAddressDeny=`, but systemd warns that they
configure an IP firewall without running as root. Treat those directives as
defense in depth rather than relying on them instead of the loopback bind.
OpenCode's memory, HSD, and local-harness integrations run as local stdio
processes. Codex, OpenCode, Hermes, the llama.cpp Web UI, and Pi can connect to
the shared Exa endpoint at `http://127.0.0.1:8769/mcp`; Pi uses the
`pi-mcp-adapter` package and the shared `~/.config/mcp/mcp.json` file. The
configured DeepWiki MCP is a remote HTTPS integration, not a local Tailscale
listener. Browser access to the Exa endpoint is restricted to the local llama
Web UI origins.

Install `uv` first. The memory wrapper also requires a separately installed
`~/.local/bin/juju-memory-mcp` executable. Then install and enable the local MCP
services with:

```bash
sudo pacman -S --needed uv nodejs npm
test -x ~/.local/bin/juju-memory-mcp
./install.sh --dry-run mcp-services
./install.sh mcp-services
systemctl --user daemon-reload
systemctl --user enable --now mcp-llama.target
systemctl --user enable --now mcp-exa.service
pi install npm:pi-mcp-adapter
```

Restart Pi after installing the adapter so it loads the shared Exa MCP entry.

The judgment wrappers expect the shared source workspace at
`~/local-model-harness` with its `.venv` installed. Use
`~/.local/bin/laya-jev-judge --backend laya` for the private local judge or
`--backend jev` for an explicit OpenRouter Jev request. The MCP equivalent is
`~/.local/bin/laya-jev-mcp`; neither wrapper changes backend implicitly.

The Friend bridge is not started by `mcp-llama.target`. It remains dormant
unless its external bridge script and function directory are installed at the
paths declared in `mcp-bridge-friend.service`.

Install a subset by naming packages:

```bash
./install.sh zsh foot qtile
```

`install.sh` only manages symlinks. Applications and feature dependencies remain explicit so the script does not turn into a surprise package-manager séance.

The Labwc and full Quickshell desktops have been retired and archived under
`legacy/`. A minimal Quickshell bar remains available for Hyprland. The
alternate qtile session expects:

```bash
sudo pacman -S --needed qtile qtile-extras python-pywlroots python-pywayland hypridle wlopm wlr-randr xorg-xrandr fuzzel mako swaybg foot wallust libnotify grim slurp wl-clipboard wtype cliphist tesseract wf-recorder network-manager-applet polkit-kde-agent papirus-icon-theme ranger pcmanfm pulsemixer pavucontrol xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
```

Active Wayland launchers use standalone `foot` processes so each new terminal
has an independent instance and server lifecycle. The optional
`foot-server.socket`/`footclient` mode is not used by the default launchers.

The active Hyprland session expects:

```bash
sudo pacman -S --needed hyprland hypridle hyprpaper quickshell fuzzel foot filezilla jq pipewire-pulse libnotify polkit wallust python-pywayland adw-gtk-theme wl-clipboard ffmpeg grim slurp wf-recorder cliphist tesseract xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-hyprland librewolf helium-browser-bin
```

Hyprland loads `~/.config/hypr/hyprland.lua` as its live provider, with
monitors, workspaces, keybindings, and rules split into Lua modules. The
adjacent `hyprland.conf` remains synchronized as a rollback and monitor-layout
reference for session helpers.

Hyprland uses Fuzzel for its application, favorites, tools, window, power,
clipboard-history, keybinding, screen-management, and live-agent-command menus.
`Super+Ctrl+Shift+number` moves every window on the current workspace to that
numbered workspace, then focuses it. It leaves windows untouched and shows a
notification when a special workspace is visible.
`Super+F2` groups live commands by their recognized agent (`codex`, `opencode`,
`claude`, `aider`, `gemini`, or `amp`), focuses an existing terminal
when one exists, and otherwise opens a read-only Foot process monitor for the
hidden command. The tools menu
also covers screen recording, an emoji/Unicode picker, OCR, and a wallpaper
picker with cached thumbnail previews that can either regenerate the Wallust
theme or keep the current palette.

The minimal Hyprland bar watches Wallust's generated palette, so
`wallust theme <name>` updates its background, text, hover, border, and accent
colors without restarting Quickshell.

Renamed workspaces set through `fuzzel-tools` appear as `id: title` in the bar;
default numeric workspaces stay compact. The bar listens for Hyprland's rename
event and refreshes its workspace model, so no Quickshell restart is needed.

`Super+grave` (the key printed as `` ` ``) cycles the focused workspace through
the configured `master`, `dwindle`, `scrolling`, and `monocle` layouts. For about
2.2 seconds after the change, the center title badge shows the selected layout
and slides vertically before returning to the active window title.

The bar also includes an ExpressVPN status chip when the ExpressVPN 5 client is
installed and activated. The chip polls `/usr/local/bin/expressvpnctl`, uses the
accent color while connected, and connects to the saved location or disconnects
on click without changing the selected region, protocol, or Network Lock.

The bar also includes game-mode and VPN controls, a Tailscale up/down toggle,
and a dedicated local grammar-correction model toggle. The correction icon
switches to a rotating, pulsing star while the `Super+;` focused-field action
is processing. The Tailscale chip shows the local address, exit node, and
online-peer count in its tooltip.

Install the correction model as machine-local data, then reload the tracked
user unit. The service is intentionally not enabled at login; click its bar
icon to start or stop it:

```bash
hf download redromnon/LFM2-700M-grammar-correction LFM2-700M.Q4_K_M.gguf \
  --local-dir ~/models/LFM2-700M-grammar-correction
systemctl --user daemon-reload
```

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

Fuzzel reads its colors from Wallust's generated cache, so apply one palette
once after a fresh install with `wallust run <wallpaper> --skip-sequences` or
`wallust theme <name> --skip-sequences` before launching a menu.

Enable the generated-file watcher once after Stowing the Wallust package:

```bash
systemctl --user enable --now wallust-refresh-desktop.path
```

The `mako` package is qtile's notification daemon, launched from qtile's
autostart.

The shared idle-inhibit bindings in Hyprland, qtile, Sway, and the retained Eww
bar use the `wayland-idle-inhibitor.py` helper installed by the `environment`
package. It requires the Arch `python-pywayland` package; install the package
before enabling those bindings.

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

The interface font is `Comic Code`. It is a commercial typeface not packaged in
the official repositories, so install it manually into
`~/.local/share/fonts/`.

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
loopback-only Anthropic-compatible endpoint. Install its audited local package, create
`~/.cli-proxy-api/config.yaml` and `client-token` as machine-local
credentials, then authenticate and enable its user service:

```bash
sudo pacman -S --needed cli-proxy-api-bin
cli-proxy-api -config ~/.cli-proxy-api/config.yaml -claude-login
cli-proxy-api -config ~/.cli-proxy-api/config.yaml -codex-login
systemctl --user enable --now cli-proxy-api.service
```

The `claudex` Zsh function launches Claude Code through that gateway while
ordinary `claude` continues to use its native configuration.

The local Matrix homeserver runs Synapse v1.156.0 in a rootless Podman container. The service expects a pre-provisioned `~/.local/share/matrix-synapse` containing `homeserver.yaml` and the server signing key; on a fresh machine, generate and review those files first using the [Synapse Docker instructions](https://github.com/matrix-org/synapse/blob/develop/docker/README.md) with server name `matrix.home.arpa` and reporting disabled. The checked-in unit does not generate or overwrite them. Then install Podman and enable `matrix-synapse.service`. Federation and public registration are disabled. The Hyprland bar indicator checks the client API and Hermes gateway before showing Matrix as healthy, and game mode pauses both services and restores their previous active state. Hermes connection secrets and the phone login are machine-local files outside the repo. Phone access uses Tailscale Serve over HTTPS after Serve is enabled for the device and the phone joins the tailnet. Matrix end-to-end encryption is currently disabled, so Synapse can read stored room content. Before using shared rooms or adding other tailnet users, set `MATRIX_ALLOWED_ROOMS` for Hermes and restrict Tailscale access to the intended devices.

Game mode is available from the controller chip in the Hyprland bar or with
`Super+Alt+G`. It pauses configured nonessential user services, enables Mako
do-not-disturb, and disables compositor effects and idle handling. If the local
grammar-correction model was active, game mode stops it and restores it only
when gaming ends.

Review `MANAGED_UNITS` in `hyprland/.config/hypr/scripts/game-mode.sh` first; those user services are paused while game mode is active.

Away mode prepares the workstation for an unattended but remotely reachable
period. It refuses to activate unless Tailscale, SSH, Codex Remote Control, and
systemd user lingering are healthy; then it records and pauses expendable user
services and desktop applications, preserves the current OpenRGB profile,
disables automatic suspend, locks the session, and powers off RGB and displays.
Networking, Codex Remote Control, the Signal fallback, CLIProxyAPI, and
the Borg backup timer remain active.

```bash
sudo pacman -S --needed openrgb openssh tailscale
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
| **bitwarden** | Bitwarden CLI wrapper that keeps the temporary vault session in GNOME Keyring without storing the master password |
| **borg** | Portable, user-level encrypted backups with a daily systemd timer, cache-aware and filesystem-boundary exclusions, low-space retention recovery, and machine-local credentials/settings |
| **boxcare** | Bounded multi-host security/maintenance audits and explicit serialized updates, using a secret-free logical inventory and strict SSH behavior |
| **codex** | Codex Remote Control systemd user service plus a ChatGPT desktop launcher that keeps the default XWayland backend |
| **disk-health** | Low-overhead hourly root-filesystem space warnings with no automatic cleanup |
| **emacs** | Emacs daemon/client configuration with pixel-precise GUI resizing, Gruber Darker, and local LLM chat with an activity spinner, auto-scroll, native code highlighting, and hidden reasoning output; available as the secondary editor |
| **environment** | compositor-neutral systemd user environment.d variables, desktop MIME defaults, and portal session cleanup |
| **eww** | Legacy Eww bar retained for migration reference |
| **foot** | Foot terminal with standalone launches, optional socket-activated server/client mode, and a Wallust color include |
| **fuzzel** | Fast native Wayland application launcher and dmenu-compatible picker with a compact square theme |
| **hyprland** | Active Lua-backed Hyprland session with Hyprpaper (a two-image 30-minute slideshow), hypridle (with a fullscreen-aware idle inhibitor), keybindings, game and remotely reachable away modes, and compositor helpers |
| **mako** | Notification daemon launched by the qtile session |
| **mcp-services** | Loopback-only HTTP/SSE wrappers for shared memory, time, and Exa web search, plus judgment tools and an optional dormant Friend bridge |
| **nvim** | Neovim configuration, plugins, mappings, and the Darklime theme; the default editor |
| **qtile** | Alternate tiling Wayland session with Hyprland-style keybinds, Fuzzel-based menus, mako notifications, scratchpad dropdowns, hypridle monitor idling, and a wlr xdg-desktop-portal config |
| **quickshell** | Minimal multi-monitor Hyprland bar with Wallust-reactive colors, active-window state, game-mode/idle/correction/Hermes/local-model/VPN/Tailscale controls, aligned system-tray menus, monitor name, and clock |
| **sway** | Legacy Sway configuration |
| **herdr** | Herdr terminal-native agent multiplexer configuration |
| **helium** | Helium browser user flags, including suppression of the session-crashed/restore bubble |
| **wallust** | Wallust color-generation configuration, application templates, and live desktop refresh hook |
| **zsh** | zsh shell configuration, prompt schema, native completion, and Carapace coverage for unsupported commands |

Repository-only directories such as `scripts/`, `assets/`, `legacy/`, and `.agents/` are not Stow packages.

## Current Desktop

The active desktop is Hyprland, with `~/.config/hypr/hyprland.lua` as its live
configuration provider. It provides Fuzzel menus and the minimal Quickshell bar.
qtile remains available as an alternate Wayland session with its own Fuzzel
menus, mako notifications, scratchpad dropdowns, and idle and portal helpers.

The minimal Hyprland bar reads Wallust's generated palette, so theme changes
update its colors without restarting Quickshell.

Helium is the default browser, with LibreWolf retained as the alternate.
Default programs are centralized in the
`environment` package: session variables live in `.config/environment.d/`, and
desktop file associations live in `.config/mimeapps.list`. The interface font
is `Comic Code` across Foot, Emacs, and qtile.

The `helium` package adds a user-level browser flag that suppresses Chromium's
session-crashed/restore bubble after a compositor window close. It does not
change Helium's startup-page preference.

The editor configuration is Neovim-first. Emacs remains configured and
available as the secondary editor.

## Repository Automation

[`AGENTS.md`](AGENTS.md) explains the repository layout and safety rules for coding agents browsing the project on GitHub.

The project-local `$commit-dotfiles` skill lives at `.agents/skills/commit-dotfiles/`. It reviews the complete worktree, checks sensitive information and line endings, verifies Stow layout and documentation, runs relevant validation, and commits the intended snapshot.

See [CHANGELOG.md](CHANGELOG.md) for historical release notes.

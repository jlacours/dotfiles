# Dotfiles

Personal Arch Linux dotfiles for Hyprland, managed with [GNU Stow](https://www.gnu.org/software/stow/).

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
./install.sh zsh foot hyprland quickshell
```

`install.sh` only manages symlinks. Applications and feature dependencies remain explicit so the script does not turn into a surprise package-manager séance.

The active Hyprland and Quickshell setup also expects:

```bash
yay -S --needed hyprland hypridle quickshell foot filezilla jq pipewire-pulse libnotify polkit wallust wl-clipboard ffmpeg grim slurp wf-recorder zen-browser-bin
```

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
| **emacs** | Emacs daemon/client configuration with Gruber Darker and local LLM chat with an activity spinner, auto-scroll, native code highlighting, and hidden reasoning output |
| **environment** | systemd user environment.d variables and desktop MIME defaults: editor, terminal, browser, portals |
| **eww** | Legacy Eww bar retained for migration reference |
| **foot** | Foot terminal — the default terminal across Hyprland, quickshell scripts, and rofi; Wallust color include |
| **hyprland** | Hyprland, hypridle (with a fullscreen-aware idle inhibitor), keybindings, game mode, and compositor helpers |
| **nvim** | Neovim configuration, plugins, mappings, and the Darklime theme; the default editor |
| **qtile** | Legacy Qtile Wayland configuration |
| **quickshell** | Active bar, overlays, notification server, OSD, and desktop scripts |
| **sway** | Legacy Sway configuration |
| **tmux** | tmux terminal multiplexer configuration |
| **wallust** | Wallust color-generation configuration |
| **zsh** | zsh shell configuration, prompt schema, native completion, and Carapace coverage for unsupported commands |

Repository-only directories such as `scripts/`, `assets/`, `legacy/`, and `.agents/` are not Stow packages.

## Current Desktop

The active desktop is Hyprland plus the square Quickshell configuration, with
Wallust-derived translucent surfaces and compositor blur. It includes:

- workspace chips with per-window icons;
- AI usage, tmux, CPU governor, system metrics, and network-rate blocks;
- an output-device-aware volume indicator and PipeWire graph-rate selector;
- system tray, game mode, microphone, notification/DND, VPN, Tailscale, idle, and suspend controls;
- clock/calendar, clipboard history, keybinding overlay, notification center, and OSD;
- Wallust theme and wallpaper selection;
- TTS controls and local-model status.

Zen Browser is the default browser. Default programs are centralized in the
`environment` package: session variables live in `.config/environment.d/`, and
desktop file associations live in `.config/mimeapps.list`. Hyprland's
`$terminal`/`$webbrowser` mirror those defaults, and every other terminal
launcher composes from `$terminal`. The interface font is `Comic Code` across
Quickshell, Foot, Emacs, and Hyprland.

The Quickshell config ships generated `qmldir` files (via
`quickshell/.config/quickshell/scripts/gen-qmldir.sh`) purely to keep the QML
language server quiet. Quickshell resolves its `pragma Singleton` modules
implicitly at runtime, but `qmlls` refuses to resolve singleton members without a
real `qmldir` in the source tree — and Quickshell's own `.qmlls.ini` tooling does
not help, because `qmlls` canonicalizes its VFS symlinks back to the source. The
fix is therefore a cursed-but-working pile of generated `qmldir` files; regenerate
them after adding or renaming components. See [`quickshell/AGENTS.md`](quickshell/AGENTS.md).

The editor configuration is Neovim-first again. Emacs remains configured and
available as the secondary editor. Why did this migrate back? The owner says,
"I'm not sure about my decisions."

## Repository Automation

[`AGENTS.md`](AGENTS.md) explains the repository layout and safety rules for coding agents browsing the project on GitHub.

The project-local `$commit-dotfiles` skill lives at `.agents/skills/commit-dotfiles/`. It reviews the complete worktree, checks sensitive information and line endings, verifies Stow layout and documentation, runs relevant validation, and commits the intended snapshot.

See [CHANGELOG.md](CHANGELOG.md) for historical release notes.

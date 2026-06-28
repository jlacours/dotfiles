# Dotfiles

Personal Arch Linux dotfiles for Hyprland, managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Install

Install the repository prerequisites:

```bash
yay -S --needed git stow
git clone https://github.com/jlacours/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./install.sh --dry-run
./install.sh
```

Install a subset by naming packages:

```bash
./install.sh zsh foot hyprland quickshell
```

`install.sh` only manages symlinks. Applications and feature dependencies remain explicit so the script does not turn into a surprise package-manager séance.

The active Hyprland and Quickshell setup also expects:

```bash
yay -S --needed hyprland hypridle quickshell rofi foot jq pipewire-pulse libnotify polkit wallust wl-clipboard ffmpeg zen-browser-bin ttf-code2000
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
| **emacs** | Emacs daemon/client configuration with Gruber Darker and local LLM support |
| **environment** | systemd user environment.d variables: default terminal, browser, Electron Wayland, GTK portal, Qt portal |
| **eww** | Legacy Eww bar retained for migration reference |
| **foot** | Foot terminal configuration and Wallust color include |
| **ghostty** | Ghostty terminal configuration |
| **hyprland** | Hyprland, hypridle (with a fullscreen-aware idle inhibitor), keybindings, game mode, and compositor helpers |
| **kitty** | Kitty terminal configuration retained as an alternative |
| **qtile** | Legacy Qtile Wayland configuration |
| **quickshell** | Active bar, overlays, notification server, OSD, and desktop scripts |
| **rofi** | Application, clipboard, power, screenshot, OCR, wallpaper, and utility menus |
| **sway** | Legacy Sway configuration |
| **tmux** | tmux terminal multiplexer configuration |
| **wallust** | Wallust color-generation configuration |
| **zsh** | zsh shell configuration and prompt schema |

Repository-only directories such as `scripts/`, `assets/`, `legacy/`, and `.agents/` are not Stow packages.

## Current Desktop

The active desktop is Hyprland plus the square Quickshell configuration. It includes:

- workspace chips with per-window icons;
- AI usage, tmux, CPU governor, system metrics, and network-rate blocks;
- an output-device-aware volume indicator and PipeWire graph-rate selector;
- system tray, game mode, microphone, notification/DND, VPN, Tailscale, idle, and suspend controls;
- clock/calendar, clipboard history, keybinding overlay, notification center, and OSD;
- a katakana "digital rain" flourish that washes across the bar on new notifications;
- Wallust theme and wallpaper selection;
- TTS controls and local-model status.

Zen Browser is the default browser. The interface font is `Comic Code` across Quickshell, Foot, Emacs, and Hyprland.

The editor configuration is Emacs-first, running as a user daemon with `emacsclient`. The previous Neovim configuration remains under `legacy/nvim/` and can be stowed explicitly if revived:

```bash
stow -d ~/.dotfiles/legacy -t ~ nvim
```

## Repository Automation

[`AGENTS.md`](AGENTS.md) explains the repository layout and safety rules for coding agents browsing the project on GitHub.

The project-local `$commit-dotfiles` skill lives at `.agents/skills/commit-dotfiles/`. It reviews the complete worktree, checks sensitive information and line endings, verifies Stow layout and documentation, runs relevant validation, and commits the intended snapshot.

See [CHANGELOG.md](CHANGELOG.md) for historical release notes.

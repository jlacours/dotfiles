# Dotfiles Repository Guide

This repository is meant to be understandable and installable by both humans and coding agents browsing it on GitHub.

## Start Here

1. Read `README.md` and `git status --short --branch` before editing.
2. Read any more-specific `AGENTS.md` in the package being changed.
3. Inspect the real config and its callers; do not infer behavior from directory names alone.
4. Preserve unrelated worktree changes. This repository is often edited live.

## GNU Stow Layout

Each configurable application gets one top-level Stow package. Mirror the path relative to `$HOME` inside that package:

```text
software/.config/software/config-file
shell/.shellrc
```

- Do not put standalone source projects, build trees, caches, databases, credentials, or generated state in a Stow package.
- Put reusable standalone tools in their own repository and install their executables into `~/.local/bin`.
- Add every new Stow package or companion software name to the package inventory and installation notes in `README.md`.
- `install.sh` auto-detects visible top-level Stow packages; add repo-only directories to `SKIP_DIRS`.

## Repository Areas

- `hyprland/`: compositor, idle, and tightly coupled desktop scripts.
- `quickshell/`: the active bar, overlays, notification server, OSD, and scripts. Read `quickshell/AGENTS.md` before substantial changes.
- `rofi/`, `foot/`, `ghostty/`, `kitty/`, `tmux/`, `zsh/`, `emacs/`: application packages.
- `eww/` and `sway/`: retained legacy configurations.
- `legacy/`: archived material; never stowed automatically.
- `scripts/`: repository maintenance helpers; not a Stow package.
- `.agents/skills/commit-dotfiles/`: the required whole-worktree audit and commit workflow.

Companion Rust tools live in:

- <https://github.com/jlacours/jlacours-tools>
- <https://github.com/jlacours/llama-choose>

Configurations must call those installed binaries through `~/.local/bin`, never through a repository `target/` directory.

## Safety and Portability

- Use Unix LF line endings.
- Prefer `$HOME` or `~` over a hard-coded home directory when the target syntax expands it.
- Keep secrets and machine-local artifacts out of Git. Check changed and untracked files, not only diff hunks.
- Do not change credentials or privileged configuration automatically.
- Keep local service lists and hardware-specific behavior documented where they are configured.
- Never add `Co-Authored-By` or generated-by metadata to commits.

## Validation

Run checks relevant to the changed package:

- Shell: `bash -n` or `zsh -n`.
- Hyprland: `hyprctl configerrors` after reload-sensitive edits.
- Quickshell: `qmllint` plus a live reload/smoke test when available.
- Foot: `foot --check-config`.
- Stow: `./install.sh --dry-run [packages...]`.
- Git: `git diff --check` and the `commit-dotfiles` audit script.

When asked to commit the dotfiles worktree, use `$commit-dotfiles`. It audits all staged, unstaged, and untracked files, updates documentation and installation instructions, validates affected configs, scans for sensitive information, and commits the complete intended snapshot.

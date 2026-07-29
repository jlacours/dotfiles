#!/bin/sh

# Display documented Hyprland bindings through Fuzzel.

set -eu

awk -F, '
  /^[[:space:]]*bindd[[:space:]]*=/ {
    modifiers = $1
    sub(/^[^=]*=[[:space:]]*/, "", modifiers)
    key = $2
    description = $3
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", modifiers)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", description)
    gsub(/\$mainMod/, "SUPER", modifiers)
    gsub(/[[:space:]]+/, "+", modifiers)
    printf "%-28s %s\n", modifiers "+" key, description
  }
' "${HYPR_CONFIG:-$HOME/.config/hypr/hyprland.conf}" | \
  fuzzel --dmenu --only-match --prompt "Hyprland keybindings> " >/dev/null || true

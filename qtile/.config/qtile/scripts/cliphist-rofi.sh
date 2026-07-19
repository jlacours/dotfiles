#!/bin/sh

# Clipboard history picker: cliphist through rofi, selection back onto the
# Wayland clipboard.

set -eu

selection=$(cliphist list | rofi -dmenu -p "Clipboard") || exit 0
[ -n "$selection" ] || exit 0
printf '%s' "$selection" | cliphist decode | wl-copy

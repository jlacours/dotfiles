#!/bin/sh
set -eu

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

selected=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.jxl' \) \
    -printf '%f\n' | sort | fuzzel --dmenu --only-match --prompt "Wallpaper> ") || exit 0

[ -z "$selected" ] && exit 0

wallpaper="$WALLPAPER_DIR/$selected"

exec "$HOME/.local/bin/wallpaper-apply" "$wallpaper"

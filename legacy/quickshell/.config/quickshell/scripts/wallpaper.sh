#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
DMENU="$HOME/.config/quickshell/scripts/qs-dmenu.sh"

# Note: the rofi version showed a thumbnail:// icon preview per entry; the
# quickshell overlay is text-only for now (see handoff), so this just lists
# filenames.
selected=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.jxl' \) \
    -printf '%f\n' | sort | "$DMENU" -i -no-custom -p "Wallpaper")

[ -z "$selected" ] && exit 0

wallpaper="$WALLPAPER_DIR/$selected"

"$HOME/.config/quickshell/scripts/wallpaper-apply.sh" "$wallpaper"

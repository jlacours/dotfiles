#!/bin/bash

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
HYPRPAPER_CONF="$HOME/.config/hypr/hyprpaper.conf"
DMENU="$HOME/.config/quickshell/scripts/qs-dmenu.sh"

# Note: the rofi version showed a thumbnail:// icon preview per entry; the
# quickshell overlay is text-only for now (see handoff), so this just lists
# filenames.
selected=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.jxl' \) \
    -printf '%f\n' | sort | "$DMENU" -i -p "Wallpaper")

[ -z "$selected" ] && exit 0

wallpaper="$WALLPAPER_DIR/$selected"

# Apply wallpaper
hyprctl hyprpaper wallpaper ",$wallpaper"

# Persist in hyprpaper.conf
cat > "$HYPRPAPER_CONF" <<EOF
splash = false

wallpaper {
    monitor =
    path = $wallpaper
}
EOF

notify-send -a "Wallpaper" -u low -t 3000 "Wallpaper" "Set to $selected"

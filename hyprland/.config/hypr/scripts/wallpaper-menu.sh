#!/bin/sh
set -eu

WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "Wallpaper" -u "$1" -t 2500 "Wallpaper" "$2" >/dev/null 2>&1 || true
}

die() {
    message=$1
    printf 'wallpaper-menu: %s\n' "$message" >&2
    notify critical "$message"
    exit 1
}

apply_wallpaper_only() {
    monitors=$(hyprctl -j monitors 2>/dev/null | jq -r '.[].name') ||
        die "Could not list active Hyprland monitors"
    [ -n "$monitors" ] || die "No active Hyprland monitors found"

    printf '%s\n' "$monitors" | while IFS= read -r monitor; do
        hyprctl hyprpaper wallpaper "$monitor, $wallpaper, cover" >/dev/null ||
            die "Hyprpaper could not set $(basename "$wallpaper")"
    done

    mkdir -p "$HOME/.config/hypr" "$HOME/.cache"
    hyprpaper_conf="$HOME/.config/hypr/hyprpaper.conf"
    hyprpaper_tmp=$(mktemp "${hyprpaper_conf}.XXXXXX") ||
        die "Could not prepare Hyprpaper configuration"
    trap 'rm -f "$hyprpaper_tmp"' EXIT HUP INT TERM

    printf 'splash = false\n\nwallpaper {\n    monitor =\n    path = %s\n}\n' \
        "$wallpaper" >"$hyprpaper_tmp" || die "Could not write Hyprpaper configuration"
    mv "$hyprpaper_tmp" "$hyprpaper_conf" || die "Could not save Hyprpaper configuration"
    trap - EXIT HUP INT TERM

    printf '%s\n' "$wallpaper" >"$HOME/.cache/wallust-current-wallpaper"
    notify low "Set to $(basename "$wallpaper"); kept the current theme"
}

selected=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.jxl' \) \
    -printf '%f\n' | sort | fuzzel --dmenu --only-match --prompt "Wallpaper> ") || exit 0

[ -z "$selected" ] && exit 0

wallpaper="$WALLPAPER_DIR/$selected"

action=$(printf '%s\n' \
    "Wallpaper + Wallust theme" \
    "Wallpaper only (keep current theme)" | \
    fuzzel --dmenu --only-match --prompt "Apply> ") || exit 0

case "$action" in
    "Wallpaper + Wallust theme")
        exec "$HOME/.local/bin/wallpaper-apply" "$wallpaper"
        ;;
    "Wallpaper only (keep current theme)")
        apply_wallpaper_only
        ;;
esac

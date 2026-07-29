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

selected=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.jxl' \) \
    -printf '%f\n' | sort | fuzzel --dmenu --only-match --prompt "Wallpaper> ") || exit 0

[ -z "$selected" ] && exit 0

wallpaper="$WALLPAPER_DIR/$selected"

wallust run "$wallpaper" || die "Wallust could not generate colors for $(basename "$wallpaper")"

pkill -x swaybg 2>/dev/null || true
setsid swaybg -m fill -i "$wallpaper" >/dev/null 2>&1 &
swaybg_pid=$!
sleep 0.25

if ! ps -p "$swaybg_pid" -o stat= -o comm= 2>/dev/null | \
    awk '$1 !~ /^Z/ && $2 == "swaybg" { alive = 1 } END { exit !alive }'; then
    wait "$swaybg_pid" 2>/dev/null || true
    die "swaybg could not display $(basename "$wallpaper")"
fi

basename "$wallpaper" >"$HOME/.cache/wallust-current-theme"
printf '%s\n' "$wallpaper" >"$HOME/.cache/wallust-current-wallpaper"
printf 'wallpaper\n' >"$HOME/.cache/wallust-current-source"

notify low "Set to $(basename "$wallpaper")"

#!/usr/bin/env bash
# Alternate two fixed wallpapers without regenerating the Wallust palette.
set -euo pipefail

readonly wallpaper_dir="$HOME/Pictures/Wallpapers"
readonly night="$wallpaper_dir/wallust-anime-night-garden-4k.png"
readonly dawn="$wallpaper_dir/wallust-anime-dawn-after-rain-4k.png"
readonly action="${1:-next}"

for wallpaper in "$night" "$dawn"; do
    if [[ ! -f "$wallpaper" ]]; then
        printf 'hyprpaper slideshow: missing wallpaper: %s\n' "$wallpaper" >&2
        exit 1
    fi
done

case "$action" in
    start)
        target="$night"
        ;;
    next)
        active="$(hyprctl hyprpaper listactive 2>/dev/null || true)"
        if grep -Fq -- "$night" <<<"$active"; then
            target="$dawn"
        else
            target="$night"
        fi
        ;;
    *)
        printf 'usage: %s [start|next]\n' "${0##*/}" >&2
        exit 2
        ;;
esac

# Hyprland starts hyprpaper immediately before this helper, so tolerate the
# small IPC startup race without launching a second renderer.
for _ in {1..40}; do
    if hyprctl hyprpaper listactive >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done

mapfile -t monitors < <(hyprctl -j monitors | jq -r '.[].name')
if (( ${#monitors[@]} == 0 )); then
    printf 'hyprpaper slideshow: no active Hyprland monitors\n' >&2
    exit 1
fi

for monitor in "${monitors[@]}"; do
    hyprctl hyprpaper wallpaper "$monitor, $target, cover" >/dev/null
done

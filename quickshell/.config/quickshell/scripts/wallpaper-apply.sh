#!/usr/bin/env bash

set -euo pipefail

wallpaper="${1:-}"
placement="${2:-fill}"

case "$placement" in
  fill|fit|center|tile|stretch) ;;
  *) placement="fill" ;;
esac

if [[ "$wallpaper" == "--clear" ]]; then
  if [[ "${XDG_CURRENT_DESKTOP:-}" != *labwc* ]]; then
    printf '%s\n' 'wallpaper clearing is only supported by the Labwc desktop' >&2
    exit 2
  fi

  home="${HOME:?}"
  state_dir="${XDG_STATE_HOME:-$home/.local/state}/quickshell"
  rm -f "$state_dir/win95-wallpaper" "$state_dir/win95-wallpaper-placement"

  if [[ -x "$home/.config/quickshell/scripts/qs-ipc.sh" ]]; then
    "$home/.config/quickshell/scripts/qs-ipc.sh" \
      wallpaper setWallpaper "" "$placement" >/dev/null 2>&1 || true
  fi

  exit 0
fi

if [[ -z "$wallpaper" ]]; then
  printf 'usage: %s <wallpaper-image>\n' "${0##*/}" >&2
  exit 2
fi

if [[ ! -f "$wallpaper" ]]; then
  printf 'wallpaper not found: %s\n' "$wallpaper" >&2
  exit 1
fi

home="${HOME:?}"
hyprpaper_conf="$home/.config/hypr/hyprpaper.conf"
name="$(basename "$wallpaper")"

if [[ "${XDG_CURRENT_DESKTOP:-}" == *labwc* ]]; then
  state_home="${XDG_STATE_HOME:-$home/.local/state}"
  state_dir="$state_home/quickshell"
  state_file="$state_dir/win95-wallpaper"
  placement_file="$state_dir/win95-wallpaper-placement"

  mkdir -p "$state_dir"
  printf '%s\n' "$wallpaper" > "$state_file"
  printf '%s\n' "$placement" > "$placement_file"

  if [[ -x "$home/.config/quickshell/scripts/qs-ipc.sh" ]]; then
    "$home/.config/quickshell/scripts/qs-ipc.sh" \
      wallpaper setWallpaper "$wallpaper" "$placement" >/dev/null 2>&1 || true
  fi

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Wallpaper" -u low -t 2500 \
      "Wallpaper" "Set to $name" >/dev/null 2>&1 || true
  fi

  exit 0
fi

mkdir -p "$home/.cache" "$(dirname "$hyprpaper_conf")"

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl hyprpaper preload "$wallpaper" >/dev/null 2>&1 || true
  hyprctl hyprpaper wallpaper ",$wallpaper" >/dev/null 2>&1 || true
  hyprctl hyprpaper unload unused >/dev/null 2>&1 || true
fi

cat > "$hyprpaper_conf" <<EOF
splash = false

wallpaper {
    monitor =
    path = $wallpaper
}
EOF

wallust run "$wallpaper"

printf '%s\n' "$name" > "$home/.cache/wallust-current-theme"
printf '%s\n' "$wallpaper" > "$home/.cache/wallust-current-wallpaper"
printf '%s\n' "wallpaper" > "$home/.cache/wallust-current-source"
printf '%s\n' "wallpaper" > "$home/.cache/quickshell-theme-picker-mode"

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

if command -v foot >/dev/null 2>&1; then
  foot --check-config >/dev/null 2>&1 || true
fi

if [[ -x "$home/.config/quickshell/scripts/reload-gtk.sh" ]]; then
  "$home/.config/quickshell/scripts/reload-gtk.sh" >/dev/null 2>&1 || true
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "Wallpaper" -u low -t 2500 "Wallpaper" "Set to $name" >/dev/null 2>&1 || true
fi

if [[ -x "$home/.config/quickshell/scripts/restart.sh" ]]; then
  setsid -f "$home/.config/quickshell/scripts/restart.sh" >/dev/null 2>&1 || true
fi

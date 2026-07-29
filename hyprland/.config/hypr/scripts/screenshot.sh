#!/bin/sh

# Hyprland screenshot modes with desktop-notification feedback.

set -eu

mode=${1:-output}
pictures_dir=${XDG_PICTURES_DIR:-"$HOME/Pictures"}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send --app-name="Screenshot" --urgency="$1" --expire-time=4500 \
    --icon="${4:-camera-photo}" "$2" "$3" >/dev/null 2>&1 || true
}

die() {
  printf 'hyprland-screenshot: %s\n' "$1" >&2
  notify critical "Screenshot failed" "$1" dialog-error
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

next_output() {
  mkdir -p "$pictures_dir" || die "Could not create $pictures_dir"
  timestamp=$(date '+%Y%m%d_%Hh%Mm%Ss')
  candidate="$pictures_dir/${timestamp}_grim.png"
  suffix=2
  while [ -e "$candidate" ]; do
    candidate="$pictures_dir/${timestamp}_grim-${suffix}.png"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

focused_output() {
  hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1
}

select_region() {
  geometry=$(slurp 2>/dev/null) || {
    notify low "Screenshot cancelled" "No region selected" dialog-information
    return 1
  }
  [ -n "$geometry" ] || return 1
  printf '%s\n' "$geometry"
}

capture_and_copy() {
  output=$1
  shift
  grim -l 2 "$@" "$output" || return 1
  wl-copy --type image/png <"$output"
}

require grim
require wl-copy

case "$mode" in
  output|full)
    require hyprctl
    require jq
    output_name=$(focused_output)
    [ -n "$output_name" ] || die "Could not determine the focused output"
    output=$(next_output)
    capture_and_copy "$output" -o "$output_name" || {
      rm -f "$output"
      die "grim could not capture the focused output"
    }
    notify normal "Screenshot saved and copied" "$(basename "$output")" "$output"
    ;;
  region-save)
    require slurp
    geometry=$(select_region) || exit 0
    output=$(next_output)
    capture_and_copy "$output" -g "$geometry" || {
      rm -f "$output"
      die "grim could not capture the selected region"
    }
    notify normal "Screenshot saved and copied" "$(basename "$output")" "$output"
    ;;
  region-copy)
    require slurp
    geometry=$(select_region) || exit 0
    runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
    temporary=$(mktemp "$runtime_dir/hyprland-screenshot.XXXXXX.png") || die "Could not create a temporary screenshot"
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    capture_and_copy "$temporary" -g "$geometry" || die "Could not capture and copy the selected region"
    notify normal "Screenshot copied" "Selected region copied to the clipboard" edit-copy
    ;;
  *) die "Unknown mode: $mode" ;;
esac

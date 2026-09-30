#!/bin/sh

# Wayland screenshot modes with desktop-notification feedback.

set -eu

session=${1:?Expected hyprland or qtile}
shift
case "$session" in
  hyprland) mode=${1:-output} ;;
  qtile) mode=${1:-full} ;;
  *) printf 'screenshot: unknown session: %s\n' "$session" >&2; exit 2 ;;
esac
pictures_dir=${XDG_PICTURES_DIR:-"$HOME/Pictures"}

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send --app-name="Screenshot" --urgency="$1" --expire-time=4500 \
    --icon="${4:-camera-photo}" "$2" "$3" >/dev/null 2>&1 || true
}

die() {
  printf '%s-screenshot: %s\n' "$session" "$1" >&2
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
  [ "$session" != qtile ] || require slurp
  geometry=$(slurp 2>/dev/null) || {
    notify low "Screenshot cancelled" "No region selected" dialog-information
    return 1
  }
  [ -n "$geometry" ] || {
    [ "$session" != qtile ] || notify low "Screenshot cancelled" "No region selected" dialog-information
    return 1
  }
  printf '%s\n' "$geometry"
}

capture_and_copy() {
  output=$1
  shift
  grim -l 2 "$@" "$output" || return 1
  wl-copy --type image/png <"$output"
}

# Geometry of the currently focused Qtile screen, in layout coordinates, as
# "X,Y WxH" for grim -g. Empty when Qtile cannot be queried: callers fall back
# to capturing the whole desktop.
focused_geometry() {
  qtile cmd-obj -o screen -f info 2>/dev/null | python3 -c '
import ast, sys
try:
    d = ast.literal_eval(sys.stdin.read())
    print("{},{} {}x{}".format(d["x"], d["y"], d["width"], d["height"]))
except Exception:
    pass
' || true
}

if [ "$session" = hyprland ]; then
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
else
require grim

case "$mode" in
  full)
    require wl-copy
    output=$(next_output)
    geometry=$(focused_geometry)
    if grim -l 2 ${geometry:+-g "$geometry"} "$output"; then
      wl-copy --type image/png <"$output" || \
        die "Screenshot saved, but could not copy it to the clipboard"
      notify normal "Screenshot saved and copied" "$(basename "$output")" "$output"
    else
      rm -f "$output"
      die "grim could not capture the desktop"
    fi
    ;;

  region-save)
    require wl-copy
    geometry=$(select_region) || exit 0
    output=$(next_output)
    if grim -l 2 -g "$geometry" "$output"; then
      wl-copy --type image/png <"$output" || \
        die "Screenshot saved, but could not copy it to the clipboard"
      notify normal "Screenshot saved and copied" "$(basename "$output")" "$output"
    else
      rm -f "$output"
      die "grim could not capture the selected region"
    fi
    ;;

  region-copy)
    require wl-copy
    geometry=$(select_region) || exit 0
    runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
    temporary=$(mktemp "$runtime_dir/qtile-screenshot.XXXXXX.png") || \
      die "Could not create a temporary screenshot"
    trap 'rm -f "$temporary"' EXIT HUP INT TERM

    grim -l 2 -g "$geometry" "$temporary" || \
      die "grim could not capture the selected region"
    wl-copy --type image/png <"$temporary" || \
      die "Could not copy the screenshot to the clipboard"
    notify normal "Screenshot copied" "Selected region copied to the clipboard" edit-copy
    ;;

  *)
    die "Unknown mode: $mode"
    ;;
esac
fi

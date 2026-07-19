#!/bin/sh

# Qtile screenshot modes with desktop-notification feedback.

set -eu

mode=${1:-full}
pictures_dir=${XDG_PICTURES_DIR:-"$HOME/Pictures"}

notify() {
  urgency=$1
  summary=$2
  body=$3
  icon=${4:-camera-photo}

  if command -v notify-send >/dev/null 2>&1; then
    notify-send \
      --app-name="Screenshot" \
      --urgency="$urgency" \
      --expire-time=4500 \
      --icon="$icon" \
      "$summary" "$body" >/dev/null 2>&1 || true
  fi
}

die() {
  message=$1
  printf 'qtile-screenshot: %s\n' "$message" >&2
  notify critical "Screenshot failed" "$message" dialog-error
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

select_region() {
  require slurp

  geometry=$(slurp 2>/dev/null) || {
    notify low "Screenshot cancelled" "No region selected" dialog-information
    return 1
  }

  [ -n "$geometry" ] || {
    notify low "Screenshot cancelled" "No region selected" dialog-information
    return 1
  }

  printf '%s\n' "$geometry"
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

#!/bin/sh

# Labwc screenshot modes with desktop-notification feedback.

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
  printf 'labwc-screenshot: %s\n' "$message" >&2
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


# The focused monitor, from the quickshell win95 shell (labwc itself cannot
# answer this). Empty when the shell is not running or answers with an error
# sentence ("Target not found." arrives on stdout with exit 0): callers fall
# back to capturing the whole desktop.
focused_output() {
  name=$("$HOME/.config/quickshell/scripts/qs-ipc.sh" output focused 2>/dev/null) || name=""
  case "$name" in
    *" "*) name="" ;;
  esac
  printf '%s\n' "$name"
}

require grim

case "$mode" in
  full)
    output=$(next_output)
    monitor=$(focused_output)
    if grim -l 2 ${monitor:+-o "$monitor"} "$output"; then
      notify normal "Screenshot saved" "$(basename "$output")" "$output"
    else
      rm -f "$output"
      die "grim could not capture the desktop"
    fi
    ;;

  region-save)
    geometry=$(select_region) || exit 0
    output=$(next_output)
    if grim -l 2 -g "$geometry" "$output"; then
      notify normal "Screenshot saved" "$(basename "$output")" "$output"
    else
      rm -f "$output"
      die "grim could not capture the selected region"
    fi
    ;;

  region-copy)
    require wl-copy
    geometry=$(select_region) || exit 0
    runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
    temporary=$(mktemp "$runtime_dir/labwc-screenshot.XXXXXX.png") || \
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

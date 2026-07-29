#!/usr/bin/env bash
#
# qs-dmenu.sh — dmenu-compatible shim on top of the active Quickshell menu.
# The square profile renders CenterMenu; Labwc's Win95 profile renders its own
# exact-size native popup. Reads newline-separated entries on stdin, shows them,
# blocks until the user picks one (or cancels),
# and prints the result to stdout — a drop-in replacement for `rofi -dmenu`
# in the scripts this repo used to shell out to.
#
# Supported subset of rofi -dmenu flags (enough to cover
# quickshell/.config/quickshell/scripts/{todo,wallpaper,emojis,cliphist,
# screenshot,screenrecord,deactivate-screens,claude,speak}.sh and
# rofi-configs.py — the whole rofi flag surface is not reimplemented):
#
#   -p PROMPT        Prompt / title text shown in the overlay header.
#   -i               Accepted, ignored — filtering is always case-insensitive.
#   -no-custom       Only allow selecting an existing row; freeform text is
#                    rejected instead of being returned as a "custom" pick.
#   -format FMT      's' (default): print the selected line's text.
#                    'i': print the 0-based row index (-1 for typed text with
#                    no match, when -no-custom is absent).
#                    'i s': print "<index> <text>" (matches rofi's -format).
#   -selected-row N  Open with the requested existing row highlighted.
#   -lines N, -theme *, -theme-str *, -show-icons
#                    Accepted, ignored — sizing/theming is fixed by the
#                    the active Quickshell profile, not by the caller.
#
# Usage: printf '%s\n' "${options[@]}" | qs-dmenu.sh -p "Prompt" [flags]
#
# Protocol: this script writes stdin to a temp file, creates a one-shot FIFO,
# asks quickshell (via scripts/qs-ipc.sh) to open the menu overlay with those
# paths, then blocks reading the FIFO. The active profile reads the item file
# and writes "<index>\t<text>" to the FIFO on selection (index -1 for free-typed
# custom text) or an empty string on cancel, then this script formats it.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prompt=""
no_custom="0"
format="s"
selected_row="0"

while [ $# -gt 0 ]; do
  case "$1" in
    -p) prompt="${2:-}"; shift 2 ;;
    -i) shift ;;
    -no-custom) no_custom="1"; shift ;;
    -format) format="${2:-s}"; shift 2 ;;
    -selected-row) selected_row="${2:-0}"; shift 2 ;;
    -lines) shift 2 ;;
    -theme) shift 2 ;;
    -theme-str) shift 2 ;;
    -show-icons) shift ;;
    *) shift ;;
  esac
done

monitor="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null || true)"

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
items_file="$(mktemp "$runtime_dir/qs-dmenu-items.XXXXXX")"
fifo="$(mktemp -u "$runtime_dir/qs-dmenu.XXXXXX")"
cat > "$items_file"
mkfifo -m 600 "$fifo"
trap 'rm -f "$fifo" "$items_file"' EXIT

if ! "$script_dir/qs-ipc.sh" menu openDmenuFile "$monitor" "$prompt" "$items_file" "$no_custom" "$selected_row" "$fifo"; then
  echo "qs-dmenu: failed to reach quickshell" >&2
  exit 1
fi

raw="$(cat "$fifo")"

if [ -z "$raw" ]; then
  exit 0
fi

result_idx="${raw%%$'\t'*}"
result_text="${raw#*$'\t'}"

case "$format" in
  "i s") printf '%s %s\n' "$result_idx" "$result_text" ;;
  i) printf '%s\n' "$result_idx" ;;
  *) printf '%s\n' "$result_text" ;;
esac

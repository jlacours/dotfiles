#!/usr/bin/env bash
#
# qs-dmenu.sh — dmenu-compatible shim on top of the quickshell centered menu
# overlay (menus/CenterMenu.qml). Reads newline-separated entries on stdin,
# shows them in the overlay, blocks until the user picks one (or cancels),
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
#   -selected-row N  Accepted, ignored — the overlay always opens with the
#                    first row highlighted (see handoff for why).
#   -lines N, -theme *, -theme-str *, -show-icons
#                    Accepted, ignored — sizing/theming is fixed by the
#                    square Theme singleton, not by the caller.
#
# Usage: printf '%s\n' "${options[@]}" | qs-dmenu.sh -p "Prompt" [flags]
#
# Protocol: this script creates a one-shot FIFO, asks quickshell (via
# scripts/qs-ipc.sh) to open the menu overlay with that FIFO path, then blocks
# reading it. CenterMenu.qml/MenuState.qml write "<index>\t<text>" to the FIFO
# on selection (index -1 for free-typed custom text) or an empty string on
# cancel (Escape / click-outside), then this script formats and prints it.

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

items="$(cat)"

monitor="$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor // empty' 2>/dev/null || true)"

runtime_dir="${XDG_RUNTIME_DIR:-/tmp}"
fifo="$(mktemp -u "$runtime_dir/qs-dmenu.XXXXXX")"
mkfifo -m 600 "$fifo"
trap 'rm -f "$fifo"' EXIT

if ! "$script_dir/qs-ipc.sh" menu openDmenu "$monitor" "$prompt" "$items" "$no_custom" "$selected_row" "$fifo"; then
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

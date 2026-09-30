#!/bin/sh

# Pick a cliphist entry through Fuzzel and restore it to the Wayland clipboard.

set -eu

selection=$(cliphist list | tr -d '\000' | \
  fuzzel --dmenu --only-match --prompt "Clipboard> ") || exit 0
[ -n "$selection" ] || exit 0
printf '%s' "$selection" | cliphist decode | wl-copy

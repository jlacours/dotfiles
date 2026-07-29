#!/bin/sh

# Clipboard history picker: cliphist through fuzzel, selection back onto the
# Wayland clipboard.

set -eu

selection=$(cliphist list | tr -d '\000' | \
  fuzzel --dmenu --only-match --prompt "Clipboard> ") || exit 0
[ -n "$selection" ] || exit 0
printf '%s' "$selection" | cliphist decode | wl-copy

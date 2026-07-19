#!/bin/sh

# Show the active Qtile keybindings through a rofi dmenu.

set -eu

qtile cmd-obj -o root -f display_kb 2>/dev/null | \
  rofi -dmenu -i -no-custom -p "Qtile keybindings" >/dev/null || true

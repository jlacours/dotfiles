#!/bin/sh

# Show the active Qtile keybindings through a fuzzel dmenu.

set -eu

qtile cmd-obj -o root -f display_kb 2>/dev/null | \
  fuzzel --dmenu --only-match --prompt "Qtile keybindings> " >/dev/null || true

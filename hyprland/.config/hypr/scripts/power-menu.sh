#!/bin/sh

# Hyprland session actions through Fuzzel.

set -eu

choice=$(printf '%s\n' "lock" "exit Hyprland" "suspend" "reboot" "poweroff" | \
  fuzzel --dmenu --only-match --minimal-lines --prompt "Power> ") || exit 0

case "$choice" in
  lock) loginctl lock-session ;;
  "exit Hyprland") hyprctl dispatch 'hl.dsp.exit()' ;;
  suspend) systemctl suspend ;;
  reboot) systemctl reboot ;;
  poweroff) systemctl poweroff ;;
  *) exit 0 ;;
esac

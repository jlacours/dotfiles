#!/bin/sh

# Session power menu through rofi.

set -eu

choice=$(printf '%s\n' "lock" "logout" "suspend" "reboot" "poweroff" | \
  rofi -dmenu -i -no-custom -p "Power") || exit 0

case "$choice" in
  lock)     loginctl lock-session ;;
  logout)   qtile cmd-obj -o cmd -f shutdown ;;
  suspend)  systemctl suspend ;;
  reboot)   systemctl reboot ;;
  poweroff) systemctl poweroff ;;
  *)        exit 0 ;;
esac

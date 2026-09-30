#!/bin/sh

# Wayland session actions through Fuzzel.

set -eu

session=${1:?Expected hyprland or qtile}
shift
case "$session" in
  hyprland) logout_label="exit Hyprland" ;;
  qtile) logout_label="logout" ;;
  *) printf 'power-menu: unknown session: %s\n' "$session" >&2; exit 2 ;;
esac

choice=$(printf '%s\n' "lock" "$logout_label" "suspend" "reboot" "poweroff" | \
  fuzzel --dmenu --only-match --minimal-lines --prompt "Power> ") || exit 0

case "$choice" in
  lock) loginctl lock-session ;;
  "$logout_label")
    if [ "$session" = hyprland ]; then
      hyprctl dispatch 'hl.dsp.exit()'
    else
      qtile cmd-obj -o cmd -f shutdown
    fi
    ;;
  suspend) systemctl suspend ;;
  reboot) systemctl reboot ;;
  poweroff) systemctl poweroff ;;
  *) exit 0 ;;
esac

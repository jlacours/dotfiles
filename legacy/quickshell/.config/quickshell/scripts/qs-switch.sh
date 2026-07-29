#!/usr/bin/env bash
#
# qs-switch.sh — manage the live quickshell configs: square and win95.
#
# square is the wallust-themed top bar; win95 is the retro bottom taskbar.
# The classic variant remains retired in legacy/quickshell-classic/.
#
# Usage: qs-switch.sh [restart|status|toggle|square|win95]
#   restart  kill and relaunch the currently running config (default)
#   status   print the active config name
#   toggle   flip square <-> win95
#   square   switch to the square bar
#   win95    switch to the win95 taskbar
#   classic  legacy alias; prints a retired notice and exits non-zero
#
# `restart` detects the running config from the quickshell process itself, so
# each compositor session keeps whichever bar it launched (wallust's restart
# path goes through here and must not swap bars).

set -euo pipefail

launch="$HOME/.config/quickshell/scripts/launch.sh"
state="$HOME/.cache/quickshell-config"

current_running() {
  local cmd
  cmd="$(pgrep -ax quickshell 2>/dev/null | head -n1 || true)"
  case "$cmd" in
    *"/quickshell/win95"*)  echo "win95" ;;
    *"/quickshell/square"*) echo "square" ;;
    *) echo "" ;;
  esac
}

current() {
  local cfg
  cfg="$(current_running)"
  if [[ -z "$cfg" && -r "$state" ]]; then
    cfg="$(<"$state")"
  fi
  echo "${cfg:-square}"
}

action="${1:-restart}"

case "$action" in
  status)
    current
    exit 0
    ;;
  restart)
    target="$(current)"
    ;;
  square|win95)
    target="$action"
    ;;
  toggle)
    if [[ "$(current)" == "square" ]]; then target="win95"; else target="square"; fi
    ;;
  classic)
    echo "qs-switch: the classic variant is retired (legacy/quickshell-classic/)" >&2
    exit 1
    ;;
  *)
    echo "usage: ${0##*/} [restart|status|toggle|square|win95]" >&2
    exit 2
    ;;
esac

# Kill every running quickshell instance and wait for them to exit.
mapfile -t pids < <(pgrep -x quickshell || true)
if ((${#pids[@]})); then
  kill "${pids[@]}" 2>/dev/null || true
  for _ in {1..50}; do
    pgrep -x quickshell >/dev/null || break
    sleep 0.1
  done
  pkill -9 -x quickshell 2>/dev/null || true
fi

setsid -f "$launch" "$target" >/dev/null 2>&1
echo "quickshell: $target"

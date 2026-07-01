#!/usr/bin/env bash
#
# qs-switch.sh — manage the single live quickshell config: square.
#
# The classic variant was retired to legacy/quickshell-classic/. square is now
# the only live config, so there is nothing left to switch between; this script
# survives as the entrypoint callers already depend on (hyprland $restart_bar,
# scripts/restart.sh, muscle memory) for restart + status.
#
# Usage: qs-switch.sh [restart|status]
#   restart  kill and relaunch the square bar (default)
#   status   print the active config name (always "square")
#   classic  legacy alias; prints a retired notice and exits non-zero
#
# "toggle" is intentionally gone — there is no second variant to flip to.

set -euo pipefail

launch="$HOME/.config/quickshell/scripts/launch.sh"

action="${1:-restart}"

case "$action" in
  status)
    echo "square"
    exit 0
    ;;
  restart|square)
    : # restart path — kill + relaunch below
    ;;
  classic|toggle)
    echo "qs-switch: the classic variant is retired (legacy/quickshell-classic/); square is the only live config" >&2
    exit 1
    ;;
  *)
    echo "usage: ${0##*/} [restart|status]" >&2
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

setsid -f "$launch" >/dev/null 2>&1
echo "quickshell: square"

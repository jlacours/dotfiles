#!/usr/bin/env sh
# Dispatch a Hyprland workspace command for keyboard shortcuts. The legacy
# workspace-flash endpoint belonged to the retired full Quickshell desktop and
# is not present in the active minimal bar.

if hyprctl systeminfo 2>/dev/null | grep -q '^configProvider: lua$'; then
  dispatcher=${1:-}
  argument=${2:-}
  quoted_argument=$(jq -n --arg value "$argument" '$value')

  case "$dispatcher" in
    workspace)
      hyprctl dispatch "hl.dsp.focus({ workspace = $quoted_argument })" >/dev/null
      ;;
    movefocus)
      hyprctl dispatch "hl.dsp.focus({ direction = $quoted_argument })" >/dev/null
      ;;
    *)
      printf 'unsupported Lua workspace dispatcher: %s\n' "$dispatcher" >&2
      exit 2
      ;;
  esac
else
  hyprctl dispatch "$@" >/dev/null
fi

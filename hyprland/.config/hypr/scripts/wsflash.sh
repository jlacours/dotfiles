#!/usr/bin/env sh
# Dispatch a Hyprland workspace command, then flash the resulting workspace
# number via Quickshell IPC. Bound only to keyboard shortcuts so mouse/scroll
# workspace switches do not trigger the flash.

before=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .activeWorkspace.name')

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

read -r ws monitor <<EOF
$(hyprctl monitors -j | jq -r '.[] | select(.focused) | "\(.activeWorkspace.name) \(.name)"')
EOF

# Only flash when the focused workspace actually changed (skips e.g. movefocus
# inside the same monitor where nothing meaningful changed).
[ "$ws" = "$before" ] && exit 0

# Skip the flash for special workspaces (scratchpad, dropdown, etc.)
case "$ws" in
  special:*|"") exit 0 ;;
esac

quickshell ipc call -- workspaceflash show "$ws" "$monitor" >/dev/null 2>&1 &

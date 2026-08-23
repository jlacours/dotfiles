#!/usr/bin/env bash

# Cycle layout for the focused workspace only

LAYOUTS=(master dwindle scrolling monocle)

# Get active workspace ID and its current layout
eval "$(hyprctl activeworkspace -j | jq -r '@sh "WS_ID=\(.id) current=\(.tiledLayout)"')"

# Find current index and advance
next="master"
for i in "${!LAYOUTS[@]}"; do
    if [[ "${LAYOUTS[$i]}" == "$current" ]]; then
        next="${LAYOUTS[$(( (i + 1) % ${#LAYOUTS[@]} ))]}"
        break
    fi
done

if hyprctl systeminfo 2>/dev/null | grep -q '^configProvider: lua$'; then
    quoted_workspace=$(jq -n --arg value "$WS_ID" '$value')
    quoted_layout=$(jq -n --arg value "$next" '$value')
    hyprctl eval "runtime_workspace_layout_rules = runtime_workspace_layout_rules or {}; local previous = runtime_workspace_layout_rules[$quoted_workspace]; if previous then previous:set_enabled(false) end; runtime_workspace_layout_rules[$quoted_workspace] = hl.workspace_rule({ workspace = $quoted_workspace, layout = $quoted_layout })"
else
    hyprctl keyword workspace "$WS_ID",layout:"$next"
fi

REFRESH_STAMP="/tmp/quickshell-layout-refresh.state"
date +%s > "$REFRESH_STAMP"

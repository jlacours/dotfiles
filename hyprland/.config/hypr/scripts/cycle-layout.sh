#!/usr/bin/env bash

# Cycle layout for the focused workspace only

LAYOUTS=(master dwindle scrolling monocle)

# Get the active workspace ID and its current layout. Abort before changing
# anything if the compositor query is unavailable or malformed.
workspace_json=$(hyprctl activeworkspace -j 2>/dev/null) || exit 1
WS_ID=$(jq -er '.id | numbers' <<< "$workspace_json") || exit 1
current=$(jq -er '.tiledLayout | strings' <<< "$workspace_json") || exit 1

# Find current index and advance
next="master"
direction="up"
for i in "${!LAYOUTS[@]}"; do
    if [[ "${LAYOUTS[$i]}" == "$current" ]]; then
        next_index=$(( (i + 1) % ${#LAYOUTS[@]} ))
        next="${LAYOUTS[$next_index]}"
        [[ "$next_index" -lt "$i" ]] && direction="down"
        break
    fi
done

if hyprctl systeminfo 2>/dev/null | grep -q '^configProvider: lua$'; then
    quoted_workspace=$(jq -n --arg value "$WS_ID" '$value')
    quoted_layout=$(jq -n --arg value "$next" '$value')
    hyprctl eval "runtime_workspace_layout_rules = runtime_workspace_layout_rules or {}; local previous = runtime_workspace_layout_rules[$quoted_workspace]; if previous then previous:set_enabled(false) end; runtime_workspace_layout_rules[$quoted_workspace] = hl.workspace_rule({ workspace = $quoted_workspace, layout = $quoted_layout })" || exit 1
else
    hyprctl keyword workspace "$WS_ID,layout:$next" || exit 1
fi

REFRESH_STAMP="/tmp/quickshell-layout-refresh.state"
date +%s > "$REFRESH_STAMP"

# The bar reads this short-lived event and replaces the title badge briefly.
# Write atomically so a reload cannot observe a partial JSON document.
LAYOUT_STATE="/tmp/quickshell-layout.state"
LAYOUT_STATE_TMP="${LAYOUT_STATE}.tmp.$$"
expires=$(( $(date +%s%3N) + 2200 ))
printf '{"layout":"%s","direction":"%s","expires":%s}\n' \
    "$next" "$direction" "$expires" > "$LAYOUT_STATE_TMP"
mv -f "$LAYOUT_STATE_TMP" "$LAYOUT_STATE"

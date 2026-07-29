#!/usr/bin/env bash

# Enable, disable, or restore Hyprland outputs through Fuzzel.

set -euo pipefail

HYPR_CONFIG="${HYPR_CONFIG:-$HOME/.config/hypr/hyprland.conf}"

die() {
    notify-send -u critical "Screens" "$1" 2>/dev/null || true
    exit 1
}

notify() {
    notify-send "Screens" "$1" 2>/dev/null || true
}

configured_monitor_rules() {
    [ -r "$HYPR_CONFIG" ] || die "Cannot read $HYPR_CONFIG."
    awk -F= '
        /^[[:space:]]*monitor[[:space:]]*=/ {
            rule = $2
            sub(/^[[:space:]]*/, "", rule)
            sub(/[[:space:]]*$/, "", rule)
            if (rule !~ /(^|,)disable($|,)/) print rule
        }
    ' "$HYPR_CONFIG"
}

restore_configured_screens() {
    local restored=0 rule
    while IFS= read -r rule; do
        [ -n "$rule" ] || continue
        hyprctl keyword monitor "$rule" >/dev/null
        restored=$((restored + 1))
    done < <(configured_monitor_rules)
    [ "$restored" -gt 0 ] || die "No configured monitor rules found."
    notify "Restored configured monitor layout."
}

enable_configured_screen() {
    local name=$1 rule="" candidate
    while IFS= read -r candidate; do
        [ "${candidate%%,*}" = "$name" ] || continue
        rule=$candidate
        break
    done < <(configured_monitor_rules)
    [ -n "$rule" ] || die "No configured rule found for $name."
    hyprctl keyword monitor "$rule" >/dev/null
    notify "Enabled $name."
}

command -v hyprctl >/dev/null || die "hyprctl not found."
command -v jq >/dev/null || die "jq not found."

monitors_json=$(hyprctl monitors -j 2>/dev/null) || die "Could not query Hyprland monitors."
active_count=$(jq 'length' <<<"$monitors_json")
active_names=$(jq -r '.[].name' <<<"$monitors_json")

entries=$(
    {
        echo "Restore configured screens"
        while IFS= read -r rule; do
            [ -n "$rule" ] || continue
            name=${rule%%,*}
            grep -Fxq "$name" <<<"$active_names" || echo "Enable $name (${rule#*,})"
        done < <(configured_monitor_rules)
        jq -r '.[] | "Disable \(.name) (\(.width)x\(.height) @ \(.refreshRate)Hz\(if .focused then ", focused" else "" end))"' \
            <<<"$monitors_json"
    }
)

selection=$(printf '%s\n' "$entries" | \
    fuzzel --dmenu --only-match --minimal-lines --prompt "Screens> ") || exit 0

case "$selection" in
    "Restore configured screens") restore_configured_screens ;;
    Enable\ *)
        name=${selection#Enable }
        enable_configured_screen "${name%% *}"
        ;;
    Disable\ *)
        [ "$active_count" -gt 1 ] || die "Refusing to disable the only active screen. Dramatic, but unhelpful."
        name=${selection#Disable }
        name=${name%% *}
        hyprctl keyword monitor "$name,disable" >/dev/null
        notify "Disabled $name."
        ;;
esac

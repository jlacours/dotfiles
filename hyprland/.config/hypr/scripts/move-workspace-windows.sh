#!/usr/bin/env bash

set -euo pipefail

readonly JQ="/usr/bin/jq"
readonly HYPRCTL="/usr/bin/hyprctl"

destination="${1:-}"
if [[ ! "${destination}" =~ ^([1-9]|10)$ ]]; then
    printf 'usage: %s WORKSPACE (1-10)\n' "${0##*/}" >&2
    exit 2
fi

active_workspace="$("${HYPRCTL}" activeworkspace -j | "${JQ}" -er '.id | numbers')"
focused_special_workspace="$("${HYPRCTL}" monitors -j | "${JQ}" -er \
    '[.[] | select(.focused == true)]
    | if length == 1 then (.[0].specialWorkspace.name // "")
      else error("could not identify the focused monitor") end')"
if [[ "${focused_special_workspace}" == special:* ]]; then
    message="Close or hide ${focused_special_workspace} before moving workspace windows."
    printf 'move-workspace-windows: %s\n' "${message}" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name=Hyprland "Cannot move workspace windows" "${message}" >/dev/null 2>&1 || true
    fi
    exit 1
fi

clients="$("${HYPRCTL}" clients -j)"
workspace_addresses="$("${JQ}" -cer --argjson workspace "${active_workspace}" \
    '[.[] | select(.workspace.id == $workspace) | .address]' <<<"${clients}")"
mapfile -t addresses < <(
    "${JQ}" -er '.[]' <<<"${workspace_addresses}"
)

for address in "${addresses[@]}"; do
    [[ "${address}" =~ ^0x[[:xdigit:]]+$ ]] || {
        printf 'unexpected Hyprland window address\n' >&2
        exit 1
    }
    "${HYPRCTL}" dispatch \
        "hl.dsp.window.move({ window = 'address:${address}', workspace = ${destination}, follow = false })" \
        >/dev/null
done

"${HYPRCTL}" dispatch "hl.dsp.focus({ workspace = ${destination} })" >/dev/null

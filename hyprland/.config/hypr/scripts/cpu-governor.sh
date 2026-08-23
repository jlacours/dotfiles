#!/usr/bin/env bash

set -uo pipefail

readonly GOVERNOR_HELPER="/usr/local/bin/game-mode-governor"
readonly SUDO="/usr/bin/sudo"
readonly JQ="/usr/bin/jq"

read_governor() {
    local governor

    governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null) || governor="unknown"
    printf '%s' "${governor//$'\n'/}"
}

status() {
    local governor
    governor=$(read_governor)

    "${JQ}" -cn \
        --arg governor "${governor:-unknown}" \
        --arg helper "${GOVERNOR_HELPER}" \
        '{governor: $governor, helper: $helper, available: ($governor != "unknown")}'
}

set_governor() {
    local governor="$1"

    if [[ ! -x "${GOVERNOR_HELPER}" ]]; then
        printf 'CPU governor helper is unavailable: %s\n' "${GOVERNOR_HELPER}" >&2
        return 1
    fi

    exec "${SUDO}" -n "${GOVERNOR_HELPER}" "${governor}"
}

toggle() {
    if [[ "$(read_governor)" == "performance" ]]; then
        set_governor powersave
    else
        set_governor performance
    fi
}

case "${1:-status}" in
    status)
        status
        ;;
    performance|powersave)
        set_governor "$1"
        ;;
    toggle)
        toggle
        ;;
    *)
        printf 'usage: %s {status|performance|powersave|toggle}\n' "$0" >&2
        exit 2
        ;;
esac

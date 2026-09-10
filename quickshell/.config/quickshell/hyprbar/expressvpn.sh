#!/usr/bin/env bash

set -uo pipefail

readonly EXPRESSVPNCTL="/usr/local/bin/expressvpnctl"
readonly TIMEOUT_SECONDS="5"

status() {
    local connection_state

    connection_state="$(${EXPRESSVPNCTL} --timeout "${TIMEOUT_SECONDS}" get connectionstate 2>/dev/null)" || connection_state="Disconnected"
    connection_state="${connection_state//$'\n'/}"

    /usr/bin/jq -cn --arg state "${connection_state:-Disconnected}" '{state: $state}'
}

case "${1:-status}" in
    status)
        status
        ;;
    connect)
        exec "${EXPRESSVPNCTL}" --timeout "${TIMEOUT_SECONDS}" connect
        ;;
    disconnect)
        exec "${EXPRESSVPNCTL}" --timeout "${TIMEOUT_SECONDS}" disconnect
        ;;
    toggle)
        connection_state="$(${EXPRESSVPNCTL} --timeout "${TIMEOUT_SECONDS}" get connectionstate 2>/dev/null)" \
            || connection_state="Disconnected"
        if [[ "${connection_state//$'\n'/}" == "Connected" ]]; then
            exec "${EXPRESSVPNCTL}" --timeout "${TIMEOUT_SECONDS}" disconnect
        fi
        exec "${EXPRESSVPNCTL}" --timeout "${TIMEOUT_SECONDS}" connect
        ;;
    *)
        printf 'usage: %s {status|connect|disconnect|toggle}\n' "$0" >&2
        exit 2
        ;;
esac

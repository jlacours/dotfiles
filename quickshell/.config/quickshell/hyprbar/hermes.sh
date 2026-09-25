#!/usr/bin/env bash

set -uo pipefail

readonly JQ="/usr/bin/jq"
readonly SYSTEMCTL="/usr/bin/systemctl"
readonly SIGNAL_DATA="${HOME}/.local/share/signal-cli/data/accounts.json"
readonly SIGNAL_CONFIGURE="${HOME}/.local/bin/hermes-signal-configure"
readonly CURL="/usr/bin/curl"

unit_active() {
    "${SYSTEMCTL}" --user is-active --quiet "$1"
}

status() {
    local signal_active=false gateway_active=false linked=false state tooltip

    unit_active signal-cli.service && signal_active=true
    unit_active hermes-gateway.service && gateway_active=true
    if [[ -r "${SIGNAL_DATA}" ]] && [[ "$("${JQ}" -r '.accounts | length' "${SIGNAL_DATA}" 2>/dev/null)" =~ ^[1-9][0-9]*$ ]]; then
        linked=true
    fi

    if [[ "${linked}" != true && "${gateway_active}" != true && "${signal_active}" != true ]]; then
        state="unlinked"
        tooltip="Hermes off — Signal is not linked. QR: ~/.local/share/signal-cli/hermes-link.png"
    elif [[ "${linked}" != true ]]; then
        state="partial"
        tooltip="Hermes service running, but Signal is not linked — click to stop"
    elif [[ "${gateway_active}" == true && "${signal_active}" == true ]]; then
        state="on"
        tooltip="Hermes gateway ON • Signal daemon ON"
    elif [[ "${gateway_active}" == true || "${signal_active}" == true ]]; then
        state="partial"
        tooltip="Hermes partially running • gateway=${gateway_active}, Signal=${signal_active}"
    else
        state="off"
        tooltip="Hermes gateway OFF • click to start Hermes + Signal"
    fi

    # shellcheck disable=SC2016
    "${JQ}" -cn \
        --arg state "${state}" \
        --arg tooltip "${tooltip}" \
        --argjson linked "${linked}" \
        --argjson gateway "${gateway_active}" \
        --argjson signal "${signal_active}" \
        --argjson available "$([[ "${linked}" == true || "${gateway_active}" == true || "${signal_active}" == true ]] && echo true || echo false)" \
        '{state:$state, active:($state == "on"), available:$available, gateway:$gateway, signal:$signal, tooltip:$tooltip}'
}

wait_for_signal() {
    local attempt
    for attempt in {1..30}; do
        : "${attempt}"
        if "${CURL}" -fsS --max-time 2 http://127.0.0.1:8080/api/v1/check >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

toggle() {
    local signal_active=false gateway_active=false
    unit_active signal-cli.service && signal_active=true
    unit_active hermes-gateway.service && gateway_active=true

    if [[ "${gateway_active}" == true || "${signal_active}" == true ]]; then
        "${SYSTEMCTL}" --user stop hermes-gateway.service signal-cli.service >/dev/null 2>&1 || true
        return
    fi

    "${SIGNAL_CONFIGURE}" >/dev/null 2>&1 || exit 2
    "${SYSTEMCTL}" --user start signal-cli.service || exit 1
    if ! wait_for_signal; then
        "${SYSTEMCTL}" --user stop signal-cli.service >/dev/null 2>&1 || true
        exit 1
    fi
    "${SYSTEMCTL}" --user start hermes-gateway.service
}

case "${1:-status}" in
    status) status ;;
    toggle) toggle ;;
    *) printf 'usage: %s {status|toggle}\n' "$0" >&2; exit 2 ;;
esac

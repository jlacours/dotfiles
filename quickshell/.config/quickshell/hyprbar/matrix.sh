#!/usr/bin/env bash

set -uo pipefail

readonly JQ="/usr/bin/jq"
readonly SYSTEMCTL="/usr/bin/systemctl"
readonly CURL="/usr/bin/curl"
readonly SERVER_UNIT="matrix-synapse.service"
readonly GATEWAY_UNIT="hermes-matrix-gateway.service"
readonly GAME_MODE="${HOME}/.config/hypr/scripts/game-mode.sh"
readonly HEALTH_URL="http://127.0.0.1:8008/_matrix/client/versions"

unit_active() {
    "${SYSTEMCTL}" --user is-active --quiet "$1"
}

game_mode_active() {
    [[ -x "${GAME_MODE}" ]] && [[ "$("${GAME_MODE}" status 2>/dev/null)" == "on" ]]
}

server_healthy() {
    "${CURL}" -fsS --max-time 2 "${HEALTH_URL}" 2>/dev/null \
        | "${JQ}" -e '(.versions | type) == "array" and (.versions | length) > 0' >/dev/null
}

status() {
    local server_active=false gateway_active=false healthy=false paused=false
    local active=false partial=false available=true class tooltip

    unit_active "${SERVER_UNIT}" && server_active=true
    unit_active "${GATEWAY_UNIT}" && gateway_active=true
    [[ "${server_active}" == true ]] && server_healthy && healthy=true

    if game_mode_active; then
        paused=true
        available=false
        class="matrix-paused"
        tooltip="Matrix paused by game mode"
    elif [[ "${server_active}" == true && "${gateway_active}" == true && "${healthy}" == true ]]; then
        active=true
        class="matrix-on"
        tooltip="Matrix homeserver and Hermes gateway are on"
    elif [[ "${server_active}" == true || "${gateway_active}" == true ]]; then
        partial=true
        class="matrix-partial"
        if [[ "${server_active}" == true && "${healthy}" != true ]]; then
            tooltip="Matrix service is active, but its client API is not responding"
        elif [[ "${server_active}" != true ]]; then
            tooltip="Hermes Matrix gateway is on, but the homeserver is off"
        else
            tooltip="Matrix homeserver is on; Hermes Matrix gateway is off"
        fi
    else
        class="matrix-off"
        tooltip="Matrix is off — click to start the homeserver and Hermes gateway"
    fi

    "${JQ}" -cn \
        --arg class "${class}" \
        --arg tooltip "${tooltip}" \
        --argjson active "${active}" \
        --argjson partial "${partial}" \
        --argjson available "${available}" \
        --argjson server "${server_active}" \
        --argjson gateway "${gateway_active}" \
        --argjson healthy "${healthy}" \
        --argjson paused "${paused}" \
        '{text:$class, class:$class, alt:"󰒋", tooltip:$tooltip, active:$active,
          partial:$partial, available:$available, server:$server, gateway:$gateway,
          healthy:$healthy, paused:$paused}'
}

start_stack() {
    local attempt
    "${SYSTEMCTL}" --user start "${SERVER_UNIT}" || return 1
    for (( attempt=0; attempt<60; attempt++ )); do
        server_healthy && break
        sleep 1
    done
    server_healthy || return 1
    "${SYSTEMCTL}" --user start "${GATEWAY_UNIT}"
}

stop_stack() {
    "${SYSTEMCTL}" --user stop "${GATEWAY_UNIT}" "${SERVER_UNIT}"
}

toggle() {
    game_mode_active && return 0
    if unit_active "${SERVER_UNIT}" && unit_active "${GATEWAY_UNIT}" && server_healthy; then
        stop_stack
    else
        start_stack
    fi
}

case "${1:-status}" in
    status) status ;;
    start) game_mode_active || start_stack ;;
    stop) stop_stack ;;
    toggle) toggle ;;
    *) printf 'usage: %s {status|start|stop|toggle}\n' "$0" >&2; exit 2 ;;
esac

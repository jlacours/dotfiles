#!/usr/bin/env bash
set -uo pipefail

UNIT="llm-corrector.service"
ENDPOINT="http://127.0.0.1:3003"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/llm-corrector"
WORKING_FILE="${RUNTIME_DIR}/working"
GAME_MODE="${HOME}/.config/hypr/scripts/game-mode.sh"

game_mode_active() {
    [[ -x "${GAME_MODE}" ]] && [[ "$("${GAME_MODE}" status 2>/dev/null)" == "on" ]]
}

working_active() {
    [[ -r "${WORKING_FILE}" ]] || return 1
    local pid
    read -r pid < "${WORKING_FILE}" || return 1
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
        return 0
    fi
    rm -f -- "${WORKING_FILE}"
    return 1
}

model_ready() {
    curl --silent --fail --max-time 0.4 "${ENDPOINT}/health" >/dev/null 2>&1 \
        && curl --silent --fail --max-time 0.4 "${ENDPOINT}/v1/models" 2>/dev/null \
            | jq -e '.data[]? | select(.id == "llm-corrector")' >/dev/null
}

emit_status() {
    local state="off"
    local tooltip="Correction off — click to enable"
    local active=false
    local working=false

    if game_mode_active; then
        state="paused"
        tooltip="Correction paused by game mode"
    elif systemctl --user is-active --quiet "${UNIT}"; then
        active=true
        if working_active; then
            state="processing"
            working=true
            tooltip="Correcting text…"
        elif model_ready; then
            state="on"
            tooltip="Correction on — click to disable"
        else
            state="starting"
            tooltip="Starting correction model…"
        fi
    elif systemctl --user is-failed --quiet "${UNIT}"; then
        state="error"
        tooltip="Correction model failed — click to retry"
    fi

    jq -cn \
        --arg state "${state}" \
        --arg tooltip "${tooltip}" \
        --argjson active "${active}" \
        --argjson working "${working}" \
        '{state: $state, active: $active, working: $working, tooltip: $tooltip}'
}

toggle() {
    if game_mode_active; then
        notify-send -a llm-corrector -u low -t 2200 "LLM Corrector" "Correction is paused by game mode"
        return 1
    fi

    if systemctl --user is-active --quiet "${UNIT}"; then
        systemctl --user stop "${UNIT}"
    else
        systemctl --user reset-failed "${UNIT}" 2>/dev/null || true
        systemctl --user start "${UNIT}"
    fi
}

case "${1:-status}" in
    status) emit_status ;;
    start)
        game_mode_active && exit 1
        systemctl --user start "${UNIT}"
        ;;
    stop) systemctl --user stop "${UNIT}" ;;
    toggle) toggle ;;
    *)
        printf 'usage: %s {status|start|stop|toggle}\n' "$0" >&2
        exit 2
        ;;
esac

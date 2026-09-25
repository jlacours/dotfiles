#!/usr/bin/env bash

set -uo pipefail

readonly JQ="/usr/bin/jq"
readonly HYPRIDLE_SERVICE="hypridle.service"
readonly VIDEO_INHIBIT_SERVICE="hypridle-video-inhibit.service"

service_active() {
    systemctl --user is-active --quiet "$1"
}

status() {
    local hypridle_active=false
    local video_inhibit_active=false
    local currently_inhibiting=false
    local class tooltip alt

    if service_active "${HYPRIDLE_SERVICE}"; then
        hypridle_active=true
    fi
    if service_active "${VIDEO_INHIBIT_SERVICE}"; then
        video_inhibit_active=true
    fi

    if [[ "${video_inhibit_active}" == true ]] && \
        systemd-inhibit --list --no-pager --json=short 2>/dev/null \
            | "${JQ}" -e 'any(.[]; .who == "hypridle-video-inhibit" and .mode == "block" and ((.what | split(":")) | any(. == "idle")))' >/dev/null; then
        currently_inhibiting=true
    fi

    if [[ "${hypridle_active}" == true && "${video_inhibit_active}" == true ]]; then
        class="hypridle-on"
        tooltip="Idle timeout on (15 min) — click to disable"
    elif [[ "${hypridle_active}" == true ]]; then
        class="hypridle-partial"
        tooltip="Idle timeout on; fullscreen guard unavailable — click to repair"
    else
        class="hypridle-off"
        tooltip="Idle timeout off — click to enable"
    fi

    if [[ "${currently_inhibiting}" == true ]]; then
        alt="󰌾"
        tooltip="Fullscreen detected — idle is blocked; click to disable"
    else
        alt="󰈉"
    fi

    "${JQ}" -cn \
        --arg class "${class}" \
        --arg tooltip "${tooltip}" \
        --arg alt "${alt}" \
        --argjson active "${hypridle_active}" \
        --argjson partial "$([[ "${hypridle_active}" == true && "${video_inhibit_active}" != true ]] && printf true || printf false)" \
        --argjson inhibiting "${currently_inhibiting}" \
        '{text: $class, alt: $alt, class: $class, tooltip: $tooltip,
          active: $active, partial: $partial, inhibiting: $inhibiting, available: true}'
}

start_services() {
    systemctl --user start "${HYPRIDLE_SERVICE}" "${VIDEO_INHIBIT_SERVICE}"
}

stop_services() {
    systemctl --user stop "${VIDEO_INHIBIT_SERVICE}" "${HYPRIDLE_SERVICE}"
}

toggle() {
    if service_active "${HYPRIDLE_SERVICE}" && service_active "${VIDEO_INHIBIT_SERVICE}"; then
        stop_services
    else
        start_services
    fi
}

case "${1:-status}" in
    status)
        status
        ;;
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    toggle)
        toggle
        ;;
    *)
        printf 'usage: %s {status|start|stop|toggle}\n' "$0" >&2
        exit 2
        ;;
esac

#!/usr/bin/env bash

set -uo pipefail

readonly TAILSCALE="/usr/bin/tailscale"
readonly JQ="/usr/bin/jq"
readonly STATUS_TIMEOUT="5s"
readonly TOGGLE_TIMEOUT="30s"

disconnected_status() {
    local available="$1"
    local class="$2"
    local tooltip="$3"

    "${JQ}" -cn \
        --arg available "${available}" \
        --arg class "${class}" \
        --arg tooltip "${tooltip}" \
        '{text: "OFF", alt: "󰖃", class: $class, tooltip: $tooltip, available: ($available == "true")}'
}

status() {
    local json backend self_ip exit_node peers

    if [[ ! -x "${TAILSCALE}" ]]; then
        disconnected_status false "tailscale-unavailable" "Tailscale is unavailable"
        return
    fi

    json="$(/usr/bin/timeout "${STATUS_TIMEOUT}" "${TAILSCALE}" status --json 2>/dev/null)" || json=""
    if [[ -z "${json}" ]]; then
        disconnected_status false "tailscale-unavailable" "Tailscale status unavailable"
        return
    fi

    backend="$("${JQ}" -r '.BackendState // "Stopped"' <<<"${json}" 2>/dev/null)"
    if [[ "${backend}" != "Running" ]]; then
        disconnected_status true "tailscale-disconnected" "Tailscale is stopped"
        return
    fi

    self_ip="$("${JQ}" -r '.Self.TailscaleIPs[0] // "?"' <<<"${json}")"
    exit_node="$("${JQ}" -r '[.Peer[]? | select(.ExitNode == true) | .HostName] | first // "none"' <<<"${json}")"
    peers="$("${JQ}" -r '[.Peer[]? | select(.Online == true)] | length' <<<"${json}")"

    "${JQ}" -cn \
        --arg self_ip "${self_ip}" \
        --arg exit_node "${exit_node}" \
        --arg peers "${peers}" \
        '{text: "ON", alt: "󰖂", class: "tailscale-connected", available: true,
          tooltip: (["Tailscale IP: " + $self_ip,
                      "Exit node: " + $exit_node,
                      "Peers online: " + $peers] | join("\n"))}'
}

toggle() {
    local backend

    backend="$(/usr/bin/timeout "${STATUS_TIMEOUT}" "${TAILSCALE}" status --json 2>/dev/null \
        | "${JQ}" -r '.BackendState // "Stopped"' 2>/dev/null)" || backend="Stopped"

    if [[ "${backend}" == "Running" ]]; then
        /usr/bin/timeout "${TOGGLE_TIMEOUT}" "${TAILSCALE}" down >/dev/null 2>&1
    else
        /usr/bin/timeout "${TOGGLE_TIMEOUT}" "${TAILSCALE}" up >/dev/null 2>&1
    fi
}

case "${1:-status}" in
    status)
        status
        ;;
    toggle)
        toggle
        ;;
    *)
        printf 'usage: %s {status|toggle}\n' "$0" >&2
        exit 2
        ;;
esac

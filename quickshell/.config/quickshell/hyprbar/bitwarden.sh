#!/usr/bin/env bash

set -uo pipefail

# Bitwarden bar chip script (component Q). Relays `bw-session status --json`
# (session authority, component W) into the hyprbar chip schema and runs the
# non-prompting `lock` action. Never reads or prints vault contents; the only
# data handled is the fixed-schema status (state, deadline, message).

readonly BW_SESSION="${HOME}/.local/bin/bw-session"
readonly JQ="/usr/bin/jq"
readonly TIMEOUT="/usr/bin/timeout"
readonly STATUS_TIMEOUT="10s"
readonly LOCK_TIMEOUT="30s"

# Strips control characters (newlines, bidi, escapes) so a hostile or buggy
# message can never inject tooltip lines. Input is expected to be W's fixed
# text; this is a defensive relay-side sanitize only.
sanitize() {
    tr -d '\000-\037\200-\237' <<<"${1:-}"
}

emit() {
    local state="$1" deadline="$2" tooltip="$3"

    "${JQ}" -cn \
        --arg state "${state}" \
        --argjson deadline "${deadline}" \
        --arg tooltip "${tooltip}" \
        --arg class "bitwarden-${state}" \
        '{state: $state, deadline: $deadline, class: $class, tooltip: $tooltip}'
}

emit_error() {
    emit "error" "null" "Bitwarden — status unavailable${1:+ (${1})}"
}

format_deadline() {
    local deadline="$1"

    if [[ "${deadline}" =~ ^[0-9]+$ ]]; then
        date -d "@${deadline}" +%H:%M 2>/dev/null || true
    fi
}

status() {
    local raw state deadline message until tooltip

    if [[ ! -x "${BW_SESSION}" ]]; then
        emit_error "bw-session missing"
        return
    fi

    raw="$("${TIMEOUT}" "${STATUS_TIMEOUT}" "${BW_SESSION}" status --json 2>/dev/null)" || raw=""
    if [[ -z "${raw}" ]]; then
        emit_error
        return
    fi

    state="$("${JQ}" -r '.state // ""' <<<"${raw}" 2>/dev/null)"
    case "${state}" in
        unlocked | locked | unauthenticated | keyring-locked) ;;
        *) state="error" ;;
    esac

    deadline="$("${JQ}" -r '.deadline // "null"' <<<"${raw}" 2>/dev/null)"
    [[ "${deadline}" =~ ^[0-9]+$ ]] || deadline="null"

    message="$(sanitize "$("${JQ}" -r '.message // ""' <<<"${raw}" 2>/dev/null)")"

    case "${state}" in
        unlocked)
            until="$(format_deadline "${deadline}")"
            if [[ -n "${until}" ]]; then
                tooltip="Bitwarden — unlocked until ${until}"
            else
                tooltip="Bitwarden — unlocked"
            fi
            ;;
        locked)
            tooltip="Bitwarden — locked"
            ;;
        unauthenticated)
            tooltip="Bitwarden — not logged in"
            ;;
        keyring-locked)
            tooltip="Bitwarden — keyring locked"
            ;;
        *)
            tooltip="Bitwarden — status error"
            ;;
    esac

    if [[ -n "${message}" && "${state}" != "unlocked" && "${state}" != "locked" ]]; then
        tooltip="${tooltip}: ${message}"
    fi

    emit "${state}" "${deadline}" "${tooltip}"
}

lock() {
    if [[ ! -x "${BW_SESSION}" ]]; then
        return 1
    fi
    "${TIMEOUT}" "${LOCK_TIMEOUT}" "${BW_SESSION}" lock --reason manual >/dev/null 2>&1
}

case "${1:-status}" in
    status)
        status
        ;;
    lock)
        lock
        ;;
    *)
        printf 'usage: %s {status|lock}\n' "$0" >&2
        exit 2
        ;;
esac

#!/usr/bin/env bash

# Toggle a Wayland idle-inhibit client without depending on a retired bar
# package. Keep the PID and log in a user-owned session runtime directory so
# they cannot leak across users or boots.
set -euo pipefail

uid="$(id -u)"
runtime_dir="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
if [[ ! -d "${runtime_dir}" || ! -O "${runtime_dir}" || ! -w "${runtime_dir}" ]]; then
    printf 'idle-inhibit: no valid user runtime directory: %s\n' "${runtime_dir}" >&2
    exit 1
fi

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
pid_file="${runtime_dir}/idle-inhibit.pid"
log_file="${runtime_dir}/idle-inhibit.log"
inhibitor="${config_home}/session/wayland-idle-inhibitor.py"

pid_is_inhibitor() {
    local pid="${1:-}"
    local args

    [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
    kill -0 "${pid}" 2>/dev/null || return 1
    args=$(ps -p "${pid}" -o args= 2>/dev/null) || return 1
    [[ "${args}" == *"${inhibitor}"* ]]
}

clear_stale_state() {
    local pid=""

    if [[ -f "${pid_file}" ]]; then
        pid=$(<"${pid_file}")
    fi
    if [[ -n "${pid}" ]] && ! pid_is_inhibitor "${pid}"; then
        rm -f "${pid_file}"
    fi
}

status() {
    clear_stale_state
    if [[ -f "${pid_file}" ]]; then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

toggle() {
    mkdir -p "${runtime_dir}"
    clear_stale_state

    if [[ -f "${pid_file}" ]]; then
        kill "$(<"${pid_file}")" 2>/dev/null || true
        rm -f "${pid_file}"
        return 0
    fi

    if [[ ! -x "${inhibitor}" ]]; then
        printf 'idle-inhibit: missing executable: %s\n' "${inhibitor}" >&2
        return 1
    fi

    "${inhibitor}" >>"${log_file}" 2>&1 &
    printf '%s\n' "$!" >"${pid_file}"
}

case "${1:-status}" in
    status)
        status
        ;;
    toggle)
        toggle
        ;;
    *)
        printf 'usage: %s {status|toggle}\n' "${0##*/}" >&2
        exit 2
        ;;
esac

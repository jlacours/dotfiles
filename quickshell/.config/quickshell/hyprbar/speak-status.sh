#!/usr/bin/env bash

# Watches the `speak` TTS script (~/.local/bin/speak) for the Speak chip.
#   status  one line of JSON: state (idle|generating|talking), active, tooltip
#   stop    SIGTERM the speak process(es) and their own ffplay child, then
#           SIGKILL anything still alive after a second
# States: idle = no speak process; generating = speak running, no ffplay child
# yet; talking = speak has an ffplay child. Other ffplay processes are ignored.

set -uo pipefail

readonly PGREP="/usr/bin/pgrep"
readonly JQ="/usr/bin/jq"
readonly SLEEP="/usr/bin/sleep"
# Matches "bash /path/speak ..." (the shebang goes through env, so argv[0] is
# bash) and a direct "/path/speak ..." invocation. "speak-status.sh" does not
# match because the name must end right after "speak".
readonly SPEAK_PATTERN='^([^ ]*/)?(bash|sh) ([^ ]*/)?speak( |$)|^([^ ]*/)?speak( |$)'

speak_pids() {
    "${PGREP}" -u "${UID}" -f "${SPEAK_PATTERN}" 2>/dev/null
}

# Args: newline-separated PIDs. Prints ffplay processes whose parent is one of them.
ffplay_children() {
    local parents
    parents="$(printf '%s\n' "$1" | paste -sd, -)"
    [[ -n "${parents}" ]] || return 0
    "${PGREP}" -P "${parents}" -x ffplay 2>/dev/null
}

status() {
    local pids children state tooltip
    pids="$(speak_pids)"
    if [[ -z "${pids}" ]]; then
        state="idle"
        tooltip="Speech idle"
    else
        children="$(ffplay_children "${pids}")"
        if [[ -n "${children}" ]]; then
            state="talking"
            tooltip="Speaking"
        else
            state="generating"
            tooltip="Preparing speech"
        fi
        tooltip+=$'\nClick to stop'
    fi
    "${JQ}" -cn --arg state "${state}" --arg tooltip "${tooltip}" \
        '{state: $state, active: ($state != "idle"), tooltip: $tooltip}'
}

stop() {
    local pids children pid
    local -a targets=()
    pids="$(speak_pids)"
    [[ -n "${pids}" ]] || return 0
    children="$(ffplay_children "${pids}")"
    # Only these PIDs are ever signalled: speak itself and its direct ffplay child.
    # shellcheck disable=SC2206
    targets=(${pids} ${children})
    kill -TERM "${targets[@]}" 2>/dev/null
    "${SLEEP}" 1
    for pid in "${targets[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            kill -KILL "${pid}" 2>/dev/null
        fi
    done
    return 0
}

case "${1:-status}" in
    status) status ;;
    stop) stop ;;
    *)
        echo "usage: $0 {status|stop}" >&2
        exit 2
        ;;
esac

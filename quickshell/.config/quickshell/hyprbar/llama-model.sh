#!/usr/bin/env bash

set -uo pipefail

readonly CURL="/usr/bin/curl"
readonly JQ="/usr/bin/jq"
readonly SYSTEMCTL="/usr/bin/systemctl"
readonly PS="/usr/bin/ps"
readonly AWK="/usr/bin/awk"
readonly READLINK="/usr/bin/readlink"
readonly TR="/usr/bin/tr"
readonly LLAMA_SERVER_BIN="${HOME}/repos/llama.cpp/build/bin/llama-server"
readonly ENDPOINT="http://127.0.0.1:3002"
readonly DEFAULT_MODEL="qwen3.6-35b-a3b"

server_pids() {
    local pid executable
    while read -r pid; do
        [[ -n "${pid}" ]] || continue
        executable="$("${READLINK}" -f "/proc/${pid}/exe" 2>/dev/null)"
        [[ "${executable}" == "${LLAMA_SERVER_BIN}" ]] || continue
        # shellcheck disable=SC2016
        if "${TR}" '\0' '\n' < "/proc/${pid}/cmdline" \
            | "${AWK}" 'previous == "--port" && $0 == "3002" { found = 1 } { previous = $0 } END { exit !found }'; then
            printf '%s\n' "${pid}"
        fi
    done < <("${PS}" -u "${USER}" -o pid=)
}

status() {
    local health_response health_code health models model context params state tooltip health_status
    health_response="$("${CURL}" -sS --max-time 2 -w $'\n%{http_code}' "${ENDPOINT}/health" 2>/dev/null)" || health_response=""
    health_code="${health_response##*$'\n'}"
    health="${health_response%$'\n'*}"
    models="$("${CURL}" -fsS --max-time 2 "${ENDPOINT}/v1/models" 2>/dev/null)" || models=""
    if [[ -n "${models}" ]]; then
        model="$("${JQ}" -r '.data[0].id // empty' <<<"${models}" 2>/dev/null)"
        context="$("${JQ}" -r '.data[0].meta.n_ctx // .data[0].meta.n_ctx_train // empty' <<<"${models}" 2>/dev/null)"
        params="$("${JQ}" -r '.data[0].meta.n_params // empty | if . == "" then empty else ((tonumber / 1000000000 * 10 | round) / 10 | tostring) + "B" end' <<<"${models}" 2>/dev/null)"
    else
        model=""
        context=""
        params=""
    fi

    health_status="$("${JQ}" -r '.status // empty' <<<"${health}" 2>/dev/null)"

    if [[ "${health_code}" == "200" && "${health_status}" == "ok" && -n "${model}" ]]; then
        state="on"
        tooltip="Local model ON • ${model}"
        [[ -n "${context}" ]] && tooltip+=" • ctx ${context}"
        [[ -n "${params}" ]] && tooltip+=" • ${params} params"
        tooltip+=$'\nEndpoint: '"${ENDPOINT}"$' • click to stop'
    elif [[ -n "$(server_pids)" ]]; then
        model="${DEFAULT_MODEL}"
        if [[ "${health_code}" == "503" && "${health_status}" == "loading model" ]]; then
            state="loading"
            tooltip="Local model loading • ${model}"
        else
            state="error"
            tooltip="Local model unhealthy (${health_status}) • ${model}"
        fi
        tooltip+=$'\nEndpoint: '"${ENDPOINT}"
    else
        state="off"
        model="${DEFAULT_MODEL}"
        tooltip="Local model OFF • click to start ${model}"
    fi

    # shellcheck disable=SC2016
    "${JQ}" -cn \
        --arg state "${state}" \
        --arg model "${model}" \
        --arg tooltip "${tooltip}" \
        '{state:$state, active:($state == "on"), busy:($state == "loading"), model:$model, tooltip:$tooltip}'
}

toggle() {
    if [[ -n "$(server_pids)" ]]; then
        "${SYSTEMCTL}" --user stop llama-hermes-model.service >/dev/null 2>&1 || true
        mapfile -t matching_pids < <(server_pids)
        if ((${#matching_pids[@]})); then
            kill -INT "${matching_pids[@]}" >/dev/null 2>&1 || true
        fi
    else
        "${SYSTEMCTL}" --user start llama-hermes-model.service
    fi
}

case "${1:-status}" in
    status) status ;;
    toggle) toggle ;;
    *) printf 'usage: %s {status|toggle}\n' "$0" >&2; exit 2 ;;
esac

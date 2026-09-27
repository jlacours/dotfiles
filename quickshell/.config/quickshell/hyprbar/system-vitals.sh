#!/usr/bin/env bash

set -uo pipefail

readonly STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/quickshell-system-vitals.state"
readonly JQ="/usr/bin/jq"

read_cpu() {
    awk '/^cpu / { idle = $5 + $6; total = 0; for (i = 2; i <= NF; i++) total += $i; print total, idle; exit }' /proc/stat
}

cpu_load() {
    local current previous current_total current_idle previous_total previous_idle delta_total delta_idle
    current="$(read_cpu)"
    read -r current_total current_idle <<< "${current}"

    if [[ -r "${STATE_FILE}" ]]; then
        read -r previous_total previous_idle < "${STATE_FILE}"
    else
        previous_total="${current_total}"
        previous_idle="${current_idle}"
    fi
    printf '%s\n' "${current_total} ${current_idle}" > "${STATE_FILE}"

    delta_total=$((current_total - previous_total))
    delta_idle=$((current_idle - previous_idle))
    if (( delta_total > 0 )); then
        awk -v total="${delta_total}" -v idle="${delta_idle}" 'BEGIN { printf "%.0f", 100 * (total - idle) / total }'
    else
        printf '0'
    fi
}

memory_load() {
    awk '/^MemTotal:/ { total = $2 } /^MemAvailable:/ { available = $2 } END {
        if (total > 0) printf "%.0f", 100 * (total - available) / total
        else print 0
    }' /proc/meminfo
}

root_load() {
    df -P / 2>/dev/null | awk 'NR == 2 { gsub(/%/, "", $5); print $5 + 0; exit }'
}

max_temperature() {
    local maximum=0 value path
    for path in /sys/class/thermal/thermal_zone*/temp; do
        [[ -r "${path}" ]] || continue
        value="$(awk '{ printf "%.0f", $1 / 1000 }' "${path}")"
        (( value > maximum )) && maximum="${value}"
    done
    printf '%s' "${maximum}"
}

gpu_values() {
    local values
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        printf '%s\n' '-1 -1'
        return
    fi
    values="$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -d ' ')"
    if [[ "${values}" =~ ^([0-9]+),([0-9]+)$ ]]; then
        printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
        printf '%s\n' '-1 -1'
    fi
}

cpu="$(cpu_load)"
ram="$(memory_load)"
disk="$(root_load)"
temp="$(max_temperature)"
read -r gpu gpu_temp <<< "$(gpu_values)"
gpu="${gpu:--1}"
gpu_temp="${gpu_temp:--1}"

"${JQ}" -cn \
    --argjson cpu "${cpu:-0}" \
    --argjson ram "${ram:-0}" \
    --argjson disk "${disk:-0}" \
    --argjson temp "${temp:-0}" \
    --argjson gpu "${gpu}" \
    --argjson gpuTemp "${gpu_temp}" \
    '{cpu:$cpu,ram:$ram,disk:$disk,temp:$temp,gpu:$gpu,gpuTemp:$gpuTemp}'

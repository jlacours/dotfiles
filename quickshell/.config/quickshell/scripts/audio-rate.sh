#!/usr/bin/env bash

set -uo pipefail

status() {
    local metadata graph_rate force_rate mode ok

    # pw-metadata can remain subscribed on some versions; bound the one-shot
    # read so a bar poll can never leave a permanent child process behind.
    metadata="$(timeout 1 pw-metadata -n settings 0 2>/dev/null || true)"
    graph_rate="$(sed -n "s/.*key:'clock.rate' value:'\([^']*\)'.*/\1/p" <<<"$metadata" | tail -n 1)"
    force_rate="$(sed -n "s/.*key:'clock.force-rate' value:'\([^']*\)'.*/\1/p" <<<"$metadata" | tail -n 1)"

    graph_rate="${graph_rate:-0}"
    force_rate="${force_rate:-0}"
    [[ "$graph_rate" =~ ^[0-9]+$ ]] || graph_rate=0
    [[ "$force_rate" =~ ^[0-9]+$ ]] || force_rate=0
    mode="manual"
    [[ "$force_rate" == "0" ]] && mode="auto"
    [[ "$force_rate" != "0" ]] && graph_rate="$force_rate"
    ok=false
    [[ "$graph_rate" =~ ^[0-9]+$ && "$graph_rate" -gt 0 ]] && ok=true

    jq -cn \
        --argjson ok "$ok" \
        --arg mode "$mode" \
        --argjson graphRate "$graph_rate" \
        --argjson forcedRate "$force_rate" \
        '{ok: $ok, mode: $mode, graphRate: $graphRate, forcedRate: $forcedRate}'
}

set_rate() {
    local requested="${1:-}"

    case "$requested" in
        auto|0) requested=0 ;;
        44100|48000|96000|192000) ;;
        *)
            printf 'unsupported rate: %s\n' "$requested" >&2
            exit 2
            ;;
    esac

    pw-metadata -n settings 0 clock.force-rate "$requested" >/dev/null
    sleep 0.15
    status
}

case "${1:-status}" in
    status) status ;;
    set) set_rate "${2:-}" ;;
    *)
        printf 'usage: %s [status|set auto|44100|48000|96000|192000]\n' "$0" >&2
        exit 2
        ;;
esac

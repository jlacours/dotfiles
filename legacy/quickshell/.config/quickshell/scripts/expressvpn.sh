#!/usr/bin/env bash

set -uo pipefail

readonly CLI="/usr/local/bin/expressvpnctl"

abbreviate_location() {
  local slug="${1,,}"
  slug="${slug%-[0-9]*}"

  case "$slug" in
    *-new-york) printf 'NYC' ;;
    *-montreal) printf 'MTL' ;;
    *-toronto) printf 'TOR' ;;
    *-vancouver) printf 'YVR' ;;
    *-los-angeles) printf 'LAX' ;;
    *-san-francisco) printf 'SFO' ;;
    *-washington-dc) printf 'DC' ;;
    *-east-london|*-docklands|*-london) printf 'LON' ;;
    *)
      local place="${slug#*-}"
      awk -F- '{
        if (NF == 1) print toupper(substr($1, 1, 3))
        else {
          out = ""
          for (i = 1; i <= NF && i <= 4; i++) out = out toupper(substr($i, 1, 1))
          print out
        }
      }' <<< "$place"
      ;;
  esac
}

emit_status() {
  local state location="" short="" tooltip
  state="$($CLI --timeout 2 get connectionstate 2>/dev/null)" || state="Unavailable"

  if [[ "$state" == "Connected" ]]; then
    location="$($CLI --timeout 2 get region 2>/dev/null)" || location="unknown"
    short="$(abbreviate_location "$location")"
    tooltip="ExpressVPN connected: $location"
  else
    tooltip="ExpressVPN: $state"
  fi

  jq -cn \
    --arg state "$state" \
    --arg location "$location" \
    --arg short "$short" \
    --arg tooltip "$tooltip" \
    '{state: $state, location: $location, short: $short, tooltip: $tooltip}'
}

toggle() {
  local state
  state="$($CLI --timeout 2 get connectionstate 2>/dev/null)" || return 1
  if [[ "$state" == "Connected" ]]; then
    "$CLI" disconnect >/dev/null
  else
    "$CLI" connect >/dev/null
  fi
}

case "${1:-status}" in
  status) emit_status ;;
  toggle) toggle ;;
  *)
    printf 'usage: %s [status|toggle]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

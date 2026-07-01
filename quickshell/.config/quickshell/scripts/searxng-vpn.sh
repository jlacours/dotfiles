#!/usr/bin/env bash
#
# searxng-vpn.sh — bar helper for the SearXNG + gluetun VPN sidecar stack.
#
# The stack itself (gluetun + searxng Quadlets + ExpressVPN creds) is NOT part
# of this dotfiles repo — it is applied separately. So this helper is defensive:
# when the stack is not installed it reports a clean "not-installed" status and
# refuses to toggle, so the bar widget degrades gracefully instead of erroring.
#
# Source of truth for status: ~/.local/bin/searxng-vpn-status.sh (KEY=value).
# This script is only the guarded bar-facing entrypoint (status/toggle/logs).
#
# Usage: searxng-vpn.sh [status|toggle|logs]
#   status  emit KEY=value lines (passthrough to the canonical status script,
#           or a synthetic "not-installed" set when the stack is absent)
#   toggle  start/stop searxng-vpn.service + searxng.service (user systemd)
#   logs    open the combined service log in a terminal (ghostty)

set -uo pipefail

STATUS_SCRIPT="$HOME/.local/bin/searxng-vpn-status.sh"
GLUETUN_UNIT="searxng-vpn.service"
SEARXNG_UNIT="searxng.service"

# A unit name always contains a '.', so a non-empty list-unit-files match means
# systemd knows about the unit. Empty output ⇒ not installed.
unit_known() {
  systemctl --user list-unit-files --no-legend --no-pager "$1" 2>/dev/null \
    | grep -q '\.'
}

stack_installed() {
  [[ -x "$STATUS_SCRIPT" ]] || return 1
  unit_known "$GLUETUN_UNIT" && unit_known "$SEARXNG_UNIT"
}

emit_not_installed() {
  printf 'GLUETUN_STATE=missing\n'
  printf 'GLUETUN_HEALTH=missing\n'
  printf 'SEARXNG_STATE=missing\n'
  printf 'SEARXNG_HTTP=error\n'
  printf 'VPN_IP=unavailable\n'
  printf 'TUNNEL_STATUS=down\n'
  printf 'OVERALL=not-installed\n'
}

cmd_status() {
  if [[ -x "$STATUS_SCRIPT" ]]; then
    "$STATUS_SCRIPT"
  else
    emit_not_installed
  fi
}

current_overall() {
  cmd_status | sed -n 's/^OVERALL=//p'
}

cmd_toggle() {
  if ! stack_installed; then
    echo "searxng-vpn: stack not installed (need $STATUS_SCRIPT and the" >&2
    echo "             searxng-vpn/searxng user units). Apply the stack first." >&2
    return 1
  fi

  case "$(current_overall)" in
    ok)
      # Healthy ⇒ tear down SearXNG first, then the VPN it rides on.
      systemctl --user stop "$SEARXNG_UNIT" "$GLUETUN_UNIT"
      ;;
    *)
      # Anything else ⇒ bring the VPN up first, then SearXNG into its netns.
      systemctl --user start "$GLUETUN_UNIT" "$SEARXNG_UNIT"
      ;;
  esac
}

cmd_logs() {
  local log_cmd
  log_cmd="journalctl --user -u $GLUETUN_UNIT -u $SEARXNG_UNIT -f"

  if command -v ghostty >/dev/null 2>&1; then
    setsid -f ghostty --title="searxng-vpn-logs" \
      --wait-after-command=true -e bash -lc "$log_cmd" >/dev/null 2>&1
  elif [[ -n "${TERMINAL:-}" ]] && command -v "$TERMINAL" >/dev/null 2>&1; then
    setsid -f "$TERMINAL" -e bash -lc "$log_cmd" >/dev/null 2>&1
  elif command -v foot >/dev/null 2>&1; then
    setsid -f foot --title="searxng-vpn-logs" -e bash -lc "$log_cmd" >/dev/null 2>&1
  elif command -v kitty >/dev/null 2>&1; then
    setsid -f kitty --title="searxng-vpn-logs" -e bash -lc "$log_cmd" >/dev/null 2>&1
  else
    echo "searxng-vpn: no terminal found to open logs" >&2
    echo "             (tried ghostty, \$TERMINAL, foot, kitty)" >&2
    return 1
  fi
}

case "${1:-status}" in
  status) cmd_status ;;
  toggle) cmd_toggle ;;
  logs)   cmd_logs ;;
  *)
    echo "usage: ${0##*/} [status|toggle|logs]" >&2
    exit 2
    ;;
esac

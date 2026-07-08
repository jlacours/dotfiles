#!/usr/bin/env bash
set -uo pipefail

MANAGED_UNITS=(
  syncthing.service
  vdirsyncer.timer
  borg-backup.timer
  mcp-memory.service
  mcp-searxng.service
  mcp-time.service
  searxng.service
  searxng-vpn.service
  hermes-gateway.service
  signal-cli-hermes.service
  hsd-web.service
)

STATE_DIR="${HOME}/.local/state/game-mode"
STATE_FILE="${STATE_DIR}/state.json"
QS_IPC="${HOME}/.config/quickshell/scripts/qs-ipc.sh"

errors=()

run_step() {
  # run_step "description" cmd [args...]
  local desc="$1"; shift
  if ! "$@" 2>/dev/null; then
    errors+=("FAILED: ${desc}")
  fi
}

game_mode_on() {
  errors=()
  mkdir -p "${STATE_DIR}"

  # 1. Record current CPU governor
  local prev_governor
  prev_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "powersave")

  # 2. Stop managed units that are currently active
  local stopped_units=()
  for unit in "${MANAGED_UNITS[@]}"; do
    if systemctl --user is-active --quiet "${unit}" 2>/dev/null; then
      stopped_units+=("${unit}")
      if ! systemctl --user stop "${unit}" 2>/dev/null; then
        errors+=("FAILED: stop ${unit}")
      fi
      # Some daemons exit non-zero on SIGTERM and land in 'failed'; clear it so
      # the unit sits clean while gaming and repeated toggles don't trip the
      # systemd start-limit.
      systemctl --user reset-failed "${unit}" 2>/dev/null || true
    fi
  done

  # 3. Stop hypridle (prevents screen blank/lock/dpms mid-game)
  if ! systemctl --user stop hypridle.service 2>/dev/null; then
    errors+=("FAILED: stop hypridle.service")
  fi

  # 4. Disable Hyprland eye-candy at runtime
  run_step "disable animations" hyprctl keyword animations:enabled 0
  run_step "disable blur" hyprctl keyword decoration:blur:enabled 0
  run_step "disable shadow" hyprctl keyword decoration:shadow:enabled 0

  # 5. Set CPU governor to performance (graceful — sudo rule may not be installed yet)
  if ! sudo -n /usr/local/bin/game-mode-governor performance 2>/dev/null; then
    errors+=("CPU governor unchanged (run the install step)")
  fi

  # 6. Build stoppedUnits JSON array and write state
  local stopped_json="[]"
  if (( ${#stopped_units[@]} > 0 )); then
    stopped_json=$(printf '%s\n' "${stopped_units[@]}" | jq -R . | jq -s .)
  fi
  jq -n \
    --argjson active true \
    --argjson stoppedUnits "${stopped_json}" \
    --arg prevGovernor "${prev_governor}" \
    '{ active: $active, stoppedUnits: $stoppedUnits, prevGovernor: $prevGovernor }' \
    > "${STATE_FILE}"

  # 7. Send notification BEFORE enabling DND so it's visible
  local n_stopped="${#stopped_units[@]}"
  local body="Stopped ${n_stopped} background services - effects off - idle paused - DND on - CPU: performance"
  if (( ${#errors[@]} > 0 )); then
    local error_lines
    error_lines=$(printf '\n  - %s' "${errors[@]}")
    notify-send -a "game-mode" -u critical "Game mode ON" "${body}${error_lines}"
  else
    notify-send -a "game-mode" -u normal "Game mode ON" "${body}"
  fi

  # 8. Enable DND (must come after the notification above, since DND would
  # suppress it). If this call fails, DND is not actually on, so notifications
  # are still visible - fire a second one here so the failure isn't silently
  # dropped into an errors array nobody sees.
  if ! "${QS_IPC}" notifications setDnd true 2>/dev/null; then
    errors+=("FAILED: enable DND via IPC")
    notify-send -a "game-mode" -u critical "Game mode ON" "FAILED: enable DND via IPC"
  fi
}

game_mode_off() {
  errors=()
  mkdir -p "${STATE_DIR}"

  # Read state
  local prev_governor="powersave"
  local stopped_units=()
  if [[ -f "${STATE_FILE}" ]]; then
    prev_governor=$(jq -r '.prevGovernor // "powersave"' "${STATE_FILE}" 2>/dev/null || echo "powersave")
    mapfile -t stopped_units < <(jq -r '.stoppedUnits[]?' "${STATE_FILE}" 2>/dev/null)
  fi

  # 1. Disable DND
  if ! "${QS_IPC}" notifications setDnd false 2>/dev/null; then
    errors+=("FAILED: disable DND via IPC")
  fi

  # 2. Restore CPU governor
  if ! sudo -n /usr/local/bin/game-mode-governor "${prev_governor}" 2>/dev/null; then
    errors+=("CPU governor not restored (run the install step)")
  fi

  # 3. Reload Hyprland (restores animations/blur/shadow from hyprland.conf)
  # Note: reload does NOT re-run exec-once, so this is safe.
  run_step "hyprctl reload" hyprctl reload

  # 4. Start hypridle
  run_step "start hypridle" systemctl --user start hypridle.service

  # 5. Start only the units that were stopped by us
  if (( ${#stopped_units[@]} > 0 )); then
    for unit in "${stopped_units[@]}"; do
      if ! systemctl --user start "${unit}" 2>/dev/null; then
        errors+=("FAILED: start ${unit}")
      fi
    done
  fi

  # 6. Clear state
  jq -n '{ active: false, stoppedUnits: [], prevGovernor: "" }' > "${STATE_FILE}"

  # 7. Notification
  if (( ${#errors[@]} > 0 )); then
    local error_lines
    error_lines=$(printf '\n  - %s' "${errors[@]}")
    notify-send -a "game-mode" -u critical "Game mode OFF" "Errors:${error_lines}"
  else
    notify-send -a "game-mode" -u normal "Game mode OFF" "All services restored."
  fi
}

game_mode_toggle() {
  local active="false"
  if [[ -f "${STATE_FILE}" ]]; then
    active=$(jq -r '.active // false' "${STATE_FILE}" 2>/dev/null || echo "false")
  fi
  if [[ "${active}" == "true" ]]; then
    game_mode_off
  else
    game_mode_on
  fi
}

game_mode_status() {
  if [[ -f "${STATE_FILE}" ]]; then
    local active
    active=$(jq -r '.active // false' "${STATE_FILE}" 2>/dev/null || echo "false")
    if [[ "${active}" == "true" ]]; then
      echo "on"
    else
      echo "off"
    fi
  else
    echo "off"
  fi
}

case "${1:-}" in
  on)     game_mode_on ;;
  off)    game_mode_off ;;
  toggle) game_mode_toggle ;;
  status) game_mode_status ;;
  *)
    echo "Usage: $(basename "$0") on|off|toggle|status" >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash
set -uo pipefail

MANAGED_UNITS=(
  cli-proxy-api.service
  emacs.service
  syncthing.service
  vdirsyncer.timer
  borg-backup.timer
  mcp-memory.service
  mcp-searxng.service
  mcp-time.service
  searxng-vpn.service
  searxng.service
  hermes-gateway.service
  signal-cli-hermes.service
  hsd-web.service
  mpd.service
  mpd-mpris.service
  hypridle-video-inhibit.service
  hypridle.service
)

STATE_DIR="${HOME}/.local/state/game-mode"
STATE_FILE="${STATE_DIR}/state.json"
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

  # 2. Snapshot active units in dependency order, then stop them in reverse.
  # This keeps dependants such as mpd-mpris and searxng from disappearing
  # before their state can be recorded.
  local active_units=()
  local stopped_units=()
  for unit in "${MANAGED_UNITS[@]}"; do
    if systemctl --user is-active --quiet "${unit}" 2>/dev/null; then
      active_units+=("${unit}")
    fi
  done

  local -A stopped_map=()
  local index
  for (( index=${#active_units[@]} - 1; index >= 0; index-- )); do
    unit="${active_units[index]}"
    if systemctl --user stop "${unit}" 2>/dev/null; then
      stopped_map["${unit}"]=1
      # Some daemons exit non-zero on SIGTERM and land in 'failed'; clear it so
      # the unit sits clean while gaming and repeated toggles don't trip the
      # systemd start-limit.
      systemctl --user reset-failed "${unit}" 2>/dev/null || true
    else
      errors+=("FAILED: stop ${unit}")
    fi
  done

  # Persist the successful stops in dependency order for a safe restore.
  for unit in "${MANAGED_UNITS[@]}"; do
    if [[ -n "${stopped_map[${unit}]:-}" ]]; then
      stopped_units+=("${unit}")
    fi
  done

  # 3. Disable Hyprland eye-candy at runtime
  run_step "disable animations" hyprctl keyword animations:enabled 0
  run_step "disable blur" hyprctl keyword decoration:blur:enabled 0
  run_step "disable shadow" hyprctl keyword decoration:shadow:enabled 0

  # 4. Set CPU governor to performance (graceful — sudo rule may not be installed yet)
  if ! sudo -n /usr/local/bin/game-mode-governor performance 2>/dev/null; then
    errors+=("CPU governor unchanged (run the install step)")
  fi

  # 5. Enable Mako's real DND mode, but remember if it was already active.
  local dnd_added="false"
  if command -v makoctl >/dev/null 2>&1; then
    if ! makoctl mode 2>/dev/null | grep -Fxq 'do-not-disturb'; then
      if makoctl mode -a do-not-disturb >/dev/null 2>&1; then
        dnd_added="true"
      else
        errors+=("FAILED: enable Mako DND")
      fi
    fi
  else
    errors+=("FAILED: makoctl is unavailable")
  fi

  # 6. Build stoppedUnits JSON array and write state.
  local stopped_json="[]"
  if (( ${#stopped_units[@]} > 0 )); then
    stopped_json=$(printf '%s\n' "${stopped_units[@]}" | jq -R . | jq -s .)
  fi
  jq -n \
    --argjson active true \
    --argjson stoppedUnits "${stopped_json}" \
    --argjson dndAdded "${dnd_added}" \
    --arg prevGovernor "${prev_governor}" \
    '{ active: $active, stoppedUnits: $stoppedUnits, dndAdded: $dndAdded, prevGovernor: $prevGovernor }' \
    > "${STATE_FILE}"

  # 7. Report the transition. Critical notifications remain visible in Mako's
  # do-not-disturb mode; ordinary application noise does not.
  local n_stopped="${#stopped_units[@]}"
  local body="Stopped ${n_stopped} background services - effects off - idle paused - DND on - CPU: performance"
  if (( ${#errors[@]} > 0 )); then
    local error_lines
    error_lines=$(printf '\n  - %s' "${errors[@]}")
    notify-send -a "game-mode" -u critical "Game mode ON" "${body}${error_lines}"
  else
    notify-send -a "game-mode" -u normal "Game mode ON" "${body}"
  fi

}

game_mode_off() {
  errors=()
  mkdir -p "${STATE_DIR}"

  # Read state
  local prev_governor="powersave"
  local stopped_units=()
  local dnd_added="false"
  if [[ -f "${STATE_FILE}" ]]; then
    prev_governor=$(jq -r '.prevGovernor // "powersave"' "${STATE_FILE}" 2>/dev/null || echo "powersave")
    mapfile -t stopped_units < <(jq -r '.stoppedUnits[]?' "${STATE_FILE}" 2>/dev/null)
    dnd_added=$(jq -r '.dndAdded // false' "${STATE_FILE}" 2>/dev/null || echo "false")
  fi

  # 1. Remove only the DND mode that game mode itself added.
  if [[ "${dnd_added}" == "true" ]] && ! makoctl mode -r do-not-disturb >/dev/null 2>&1; then
    errors+=("FAILED: disable Mako DND")
  fi

  # 2. Restore CPU governor
  if ! sudo -n /usr/local/bin/game-mode-governor "${prev_governor}" 2>/dev/null; then
    errors+=("CPU governor not restored (run the install step)")
  fi

  # 3. Reload Hyprland (restores animations/blur/shadow from hyprland.conf)
  # Note: reload does NOT re-run exec-once, so this is safe.
  run_step "hyprctl reload" hyprctl reload

  # 4. Start only the units that were stopped by us.
  if (( ${#stopped_units[@]} > 0 )); then
    for unit in "${stopped_units[@]}"; do
      if ! systemctl --user start "${unit}" 2>/dev/null; then
        errors+=("FAILED: start ${unit}")
      elif [[ "${unit}" == "mpd.service" ]] && command -v mpc >/dev/null 2>&1; then
        # mpd reports active slightly before its socket accepts clients. Avoid
        # racing mpd-mpris, which otherwise exits cleanly and stays down.
        for (( attempt=0; attempt<50; attempt++ )); do
          mpc status >/dev/null 2>&1 && break
          sleep 0.1
        done
      fi
    done
  fi

  # 5. Clear state
  jq -n '{ active: false, stoppedUnits: [], dndAdded: false, prevGovernor: "" }' > "${STATE_FILE}"

  # 6. Notification
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

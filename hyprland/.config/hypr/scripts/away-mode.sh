#!/usr/bin/env bash

# Put the workstation into a low-resource, physically dark state without
# sacrificing its verified remote-control paths. State lives outside Git under
# XDG_STATE_HOME so every successful activation can restore only what it owns.
set -uo pipefail

# Dependency order for restoration. Activation stops the same list in reverse.
# Remote access, networking, credentials, and backups are deliberately absent.
MANAGED_UNITS=(
  pipewire.socket
  pipewire.service
  pipewire-pulse.socket
  pipewire-pulse.service
  wireplumber.service
  xdg-permission-store.service
  xdg-document-portal.service
  xdg-desktop-portal.service
  xdg-desktop-portal-gtk.service
  xdg-desktop-portal-hyprland.service
  at-spi-dbus-bus.service
  polkit-kde-agent.service
  'app-nm\x2dapplet@autostart.service'
  mako.service
  emacs.service
  syncthing.service
  vdirsyncer.timer
  searxng-vpn.service
  searxng.service
  mcp-memory.service
  mcp-time.service
  mcp-searxng.service
  hsd-web.service
  mpd.service
  mpd-mpris.service
  hypridle-video-inhibit.service
  hyprpaper-slideshow.timer
)

PROTECTED_USER_UNITS=(
  codex-remote-control.service
  cli-proxy-api.service
  hermes-gateway.service
  signal-cli-hermes.service
  borg-backup.timer
  hypridle.service
)

STATE_ROOT="${XDG_STATE_HOME:-${HOME}/.local/state}"
STATE_DIR="${STATE_ROOT}/away-mode"
STATE_FILE="${STATE_DIR}/state.json"
LOCK_FILE="${STATE_DIR}/lock"
RGB_PROFILE_BASE="${STATE_DIR}/openrgb-before-away"
RGB_PROFILE="${RGB_PROFILE_BASE}.orp"
SUSPEND_STATE_FILE="${STATE_ROOT}/hypridle-suspend-disabled"

errors=()
original_active_units=()
steam_was_running=false
discord_was_running=false
signal_was_running=false
quickshell_was_running=false
hyprpaper_was_running=false
herdr_was_running=false
suspend_was_disabled=false
rgb_saved=false
started_at=""

error() {
  errors+=("$1")
}

require_commands() {
  local missing=()
  local command_name

  for command_name in flock jq loginctl openrgb pgrep ss systemctl systemd-run tailscale timeout; do
    command -v "${command_name}" >/dev/null 2>&1 || missing+=("${command_name}")
  done

  if (( ${#missing[@]} > 0 )); then
    printf 'away-mode: missing required commands: %s\n' "${missing[*]}" >&2
    return 1
  fi
}

acquire_lock() {
  mkdir -p "${STATE_DIR}"
  exec 9>"${LOCK_FILE}"
  if ! flock -n 9; then
    printf 'away-mode: another transition is already running\n' >&2
    return 1
  fi
}

state_is_active() {
  [[ -f "${STATE_FILE}" ]] && jq -e '.active == true' "${STATE_FILE}" >/dev/null 2>&1
}

check_protected_units() {
  local managed_unit protected_unit

  for protected_unit in "${PROTECTED_USER_UNITS[@]}"; do
    for managed_unit in "${MANAGED_UNITS[@]}"; do
      if [[ "${managed_unit}" == "${protected_unit}" ]]; then
        printf 'away-mode: protected unit is in MANAGED_UNITS: %s\n' "${protected_unit}" >&2
        return 1
      fi
    done
  done
}

verify_reachability() {
  local failures=()
  local current_user

  current_user="$(id -un)"

  systemctl is-active --quiet tailscaled.service || failures+=("tailscaled is not active")
  systemctl is-active --quiet sshd.service || failures+=("sshd is not active")

  if ! tailscale status --json 2>/dev/null |
      jq -e '.BackendState == "Running" and .Self.Online == true and (.Self.TailscaleIPs | length > 0)' \
        >/dev/null; then
    failures+=("Tailscale is not online")
  fi

  if ! ss -H -lnt 'sport = :22' 2>/dev/null | grep -q .; then
    failures+=("nothing is listening on TCP port 22")
  fi

  if ! systemctl --user is-active --quiet codex-remote-control.service; then
    failures+=("Codex Remote Control is not active")
  elif ! pgrep -f '[c]odex app-server --remote-control' >/dev/null; then
    failures+=("the Codex remote app-server is not running")
  fi

  if [[ "$(loginctl show-user "${current_user}" -p Linger --value 2>/dev/null)" != "yes" ]]; then
    failures+=("systemd user lingering is disabled")
  fi

  if (( ${#failures[@]} > 0 )); then
    printf 'away-mode: reachability check failed:\n' >&2
    printf '  - %s\n' "${failures[@]}" >&2
    return 1
  fi

  return 0
}

process_is_running() {
  case "$1" in
    steam) pgrep -x steam >/dev/null ;;
    discord) pgrep -x Discord >/dev/null ;;
    signal) pgrep -f '[/](tmp/.*signal-desktop-beta|home/.*/signal-desktop-beta\.AppImage)' >/dev/null ;;
    quickshell) pgrep -x qs >/dev/null ;;
    hyprpaper) pgrep -x hyprpaper >/dev/null ;;
    herdr) pgrep -x herdr >/dev/null && herdr status server >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

snapshot_state() {
  local unit

  original_active_units=()
  for unit in "${MANAGED_UNITS[@]}"; do
    if systemctl --user is-active --quiet "${unit}" 2>/dev/null; then
      original_active_units+=("${unit}")
    fi
  done

  process_is_running steam && steam_was_running=true
  process_is_running discord && discord_was_running=true
  process_is_running signal && signal_was_running=true
  process_is_running quickshell && quickshell_was_running=true
  process_is_running hyprpaper && hyprpaper_was_running=true
  process_is_running herdr && herdr_was_running=true

  [[ -f "${SUSPEND_STATE_FILE}" ]] && suspend_was_disabled=true
  started_at="$(date --iso-8601=seconds)"
}

save_rgb_profile() {
  rgb_saved=false
  command -v openrgb >/dev/null 2>&1 || return 0

  rm -f "${RGB_PROFILE}" "${RGB_PROFILE}.orp"
  if timeout 30s openrgb --save-profile "${RGB_PROFILE_BASE}" --noautoconnect \
      >/dev/null 2>&1 && [[ -s "${RGB_PROFILE}" ]]; then
    rgb_saved=true
  else
    error "could not save the OpenRGB profile"
  fi
}

errors_json() {
  if (( ${#errors[@]} == 0 )); then
    printf '[]\n'
  else
    printf '%s\n' "${errors[@]}" | jq -R . | jq -s .
  fi
}

write_active_state() {
  local phase="$1"
  local units_json process_json current_errors temp_file

  units_json='[]'
  if (( ${#original_active_units[@]} > 0 )); then
    units_json="$(printf '%s\n' "${original_active_units[@]}" | jq -R . | jq -s .)"
  fi

  process_json="$(jq -n \
    --argjson steam "${steam_was_running}" \
    --argjson discord "${discord_was_running}" \
    --argjson signal "${signal_was_running}" \
    --argjson quickshell "${quickshell_was_running}" \
    --argjson hyprpaper "${hyprpaper_was_running}" \
    --argjson herdr "${herdr_was_running}" \
    '{steam: $steam, discord: $discord, signal: $signal, quickshell: $quickshell,
      hyprpaper: $hyprpaper, herdr: $herdr}')"
  current_errors="$(errors_json)"
  temp_file="$(mktemp "${STATE_DIR}/state.json.tmp.XXXXXX")" || return 1

  jq -n \
    --argjson active true \
    --arg phase "${phase}" \
    --arg startedAt "${started_at}" \
    --argjson restoreUnits "${units_json}" \
    --argjson restoreProcesses "${process_json}" \
    --argjson suspendWasDisabled "${suspend_was_disabled}" \
    --argjson rgbProfileSaved "${rgb_saved}" \
    --arg rgbProfile "${RGB_PROFILE}" \
    --argjson errors "${current_errors}" \
    '{active: $active, phase: $phase, startedAt: $startedAt,
      restoreUnits: $restoreUnits, restoreProcesses: $restoreProcesses,
      suspendWasDisabled: $suspendWasDisabled,
      rgbProfileSaved: $rgbProfileSaved, rgbProfile: $rgbProfile,
      errors: $errors}' > "${temp_file}" || {
        rm -f "${temp_file}"
        return 1
      }

  mv "${temp_file}" "${STATE_FILE}"
}

stop_managed_units() {
  local index unit

  for (( index=${#MANAGED_UNITS[@]} - 1; index >= 0; index-- )); do
    unit="${MANAGED_UNITS[index]}"
    if systemctl --user is-active --quiet "${unit}" 2>/dev/null; then
      if ! systemctl --user stop "${unit}" 2>/dev/null; then
        error "failed to stop ${unit}"
      fi
      systemctl --user reset-failed "${unit}" 2>/dev/null || true
    fi
  done
}

kill_matches() {
  local signal_name="$1" pattern="$2"
  local pids=()

  mapfile -t pids < <(pgrep -f "${pattern}" 2>/dev/null || true)
  if (( ${#pids[@]} > 0 )); then
    kill "-${signal_name}" "${pids[@]}" 2>/dev/null || true
  fi
}

kill_exact_names() {
  local signal_name="$1"
  shift

  local process_name
  for process_name in "$@"; do
    pkill "-${signal_name}" -x "${process_name}" 2>/dev/null || true
  done
}

stop_desktop_processes() {
  local attempt

  if process_is_running steam; then
    steam -shutdown >/dev/null 2>&1 || true
    for (( attempt=0; attempt<50; attempt++ )); do
      pgrep -x steam >/dev/null || break
      sleep 0.2
    done
    systemctl --user stop luna-steam.service 2>/dev/null || true
    kill_matches TERM '[/]\.local/share/Steam/.+(steam|steamwebhelper)'
  fi

  kill_matches TERM '[/]\.config/discord/(app-|Crashpad)'
  kill_matches TERM '[/](tmp/.*signal-desktop-beta|home/.*/signal-desktop-beta\.AppImage)'
  kill_exact_names TERM Discord qs hyprpaper
  herdr server stop >/dev/null 2>&1 || true

  for (( attempt=0; attempt<30; attempt++ )); do
    if ! process_is_running steam && ! process_is_running discord &&
        ! process_is_running signal && ! process_is_running quickshell &&
        ! process_is_running hyprpaper && ! process_is_running herdr; then
      return 0
    fi
    sleep 0.2
  done

  kill_matches KILL '[/]\.config/discord/(app-|Crashpad)'
  kill_matches KILL '[/](tmp/.*signal-desktop-beta|home/.*/signal-desktop-beta\.AppImage)'
  kill_exact_names KILL Discord qs hyprpaper steam steamwebhelper herdr
}

turn_rgb_off() {
  command -v openrgb >/dev/null 2>&1 || return 0

  if ! timeout 30s openrgb --mode direct --color 000000 --brightness 0 --noautoconnect \
      >/dev/null 2>&1; then
    error "failed to turn off one or more OpenRGB devices"
  fi
}

graphical_session_id() {
  loginctl list-sessions --no-legend 2>/dev/null |
    awk -v uid="$(id -u)" '$2 == uid && $4 != "-" { print $1; exit }'
}

lock_and_blank_displays() {
  local session_id

  mkdir -p "$(dirname "${SUSPEND_STATE_FILE}")"
  : > "${SUSPEND_STATE_FILE}"

  session_id="$(graphical_session_id)"
  if [[ -n "${session_id}" ]]; then
    loginctl lock-session "${session_id}" 2>/dev/null || error "failed to lock session ${session_id}"
  fi

  if command -v hyprctl >/dev/null 2>&1; then
    sleep 1
    hyprctl dispatch 'hl.dsp.dpms({ action = "off" })' >/dev/null 2>&1 || error "failed to power off the displays"
  fi
}

start_transient() {
  local name="$1"
  shift

  if systemctl --user is-active --quiet "away-mode-restore-${name}.service" 2>/dev/null; then
    return 0
  fi

  systemctl --user stop "away-mode-restore-${name}.service" 2>/dev/null || true
  systemctl --user reset-failed "away-mode-restore-${name}.service" 2>/dev/null || true
  systemd-run --user --unit="away-mode-restore-${name}.service" --collect \
    --property=Type=exec -- "$@" >/dev/null 2>&1
}

start_restore_unit() {
  local unit="$1"

  if ! systemctl --user start "${unit}" 2>/dev/null; then
    error "failed to start ${unit}"
    return
  fi

  if [[ "${unit}" == "mpd.service" ]] && command -v mpc >/dev/null 2>&1; then
    local attempt
    for (( attempt=0; attempt<50; attempt++ )); do
      mpc status >/dev/null 2>&1 && break
      sleep 0.1
    done
  fi
}

restore_processes() {
  local process_state="$1"
  local attempt process_name

  if jq -e '.herdr == true' <<<"${process_state}" >/dev/null && ! process_is_running herdr; then
    start_transient herdr herdr server || error "failed to restart Herdr"
  fi
  if jq -e '.hyprpaper == true' <<<"${process_state}" >/dev/null && ! process_is_running hyprpaper; then
    start_transient hyprpaper hyprpaper || error "failed to restart Hyprpaper"
  fi
  if jq -e '.quickshell == true' <<<"${process_state}" >/dev/null && ! process_is_running quickshell; then
    # Keep Quickshell in the foreground of the transient unit. With `-d`, the
    # launcher exits and systemd correctly cleans up the daemonized child too.
    start_transient quickshell qs -c hyprbar || error "failed to restart Quickshell"
  fi
  if jq -e '.steam == true' <<<"${process_state}" >/dev/null && ! process_is_running steam; then
    start_transient steam steam -silent || error "failed to restart Steam"
  fi
  if jq -e '.discord == true' <<<"${process_state}" >/dev/null && ! process_is_running discord; then
    start_transient discord discord --ozone-platform=x11 || error "failed to restart Discord"
  fi
  if jq -e '.signal == true' <<<"${process_state}" >/dev/null && ! process_is_running signal; then
    start_transient signal "${HOME}/.local/bin/signal-desktop-beta.AppImage" --no-sandbox || \
      error "failed to restart Signal Desktop"
  fi

  for process_name in herdr hyprpaper quickshell steam discord signal; do
    if ! jq -e ".${process_name} == true" <<<"${process_state}" >/dev/null; then
      continue
    fi
    for (( attempt=0; attempt<50; attempt++ )); do
      process_is_running "${process_name}" && break
      sleep 0.2
    done
    process_is_running "${process_name}" || error "${process_name} did not remain running after restore"
  done
}

away_mode_on() {
  require_commands || return 1
  acquire_lock || return 1
  check_protected_units || return 1
  verify_reachability || return 1

  if [[ -x "${HOME}/.config/hypr/scripts/game-mode.sh" ]] &&
      [[ "$("${HOME}/.config/hypr/scripts/game-mode.sh" status 2>/dev/null)" == "on" ]]; then
    printf 'away-mode: turn off game mode before enabling away mode\n' >&2
    return 1
  fi

  if state_is_active; then
    errors=()
    stop_managed_units
    stop_desktop_processes
    turn_rgb_off
    lock_and_blank_displays
    verify_reachability || return 1
    if (( ${#errors[@]} > 0 )); then
      printf 'Away mode was re-applied with warnings:\n' >&2
      printf '  - %s\n' "${errors[@]}" >&2
      return 2
    fi
    printf 'Away mode is already on; the low-resource state was re-applied.\n'
    return 0
  fi

  errors=()
  snapshot_state
  save_rgb_profile
  write_active_state activating || {
    printf 'away-mode: could not persist the restore state; no services were stopped\n' >&2
    return 1
  }

  stop_managed_units
  stop_desktop_processes
  turn_rgb_off
  lock_and_blank_displays

  if verify_reachability; then
    write_active_state active || error "failed to update the state file"
  else
    error "post-activation reachability verification failed"
    write_active_state active-with-errors || true
    return 1
  fi

  if (( ${#errors[@]} > 0 )); then
    write_active_state active-with-errors || true
    printf 'Away mode is on with warnings:\n' >&2
    printf '  - %s\n' "${errors[@]}" >&2
    return 2
  fi

  printf 'Away mode is on: remote access preserved, expendables stopped, RGB and displays off.\n'
}

away_mode_off() {
  local restore_units=() process_state suspend_state rgb_profile_saved deferred_timer=false
  local unit temp_file current_errors

  require_commands || return 1
  acquire_lock || return 1

  if ! state_is_active; then
    printf 'Away mode is already off.\n'
    return 0
  fi

  errors=()
  mapfile -t restore_units < <(jq -r '.restoreUnits[]?' "${STATE_FILE}" 2>/dev/null)
  process_state="$(jq -c '.restoreProcesses // {}' "${STATE_FILE}" 2>/dev/null || printf '{}')"
  suspend_state="$(jq -r '.suspendWasDisabled // false' "${STATE_FILE}" 2>/dev/null || printf false)"
  rgb_profile_saved="$(jq -r '.rgbProfileSaved // false' "${STATE_FILE}" 2>/dev/null || printf false)"

  for unit in "${restore_units[@]}"; do
    if [[ "${unit}" == "hyprpaper-slideshow.timer" ]]; then
      deferred_timer=true
      continue
    fi
    start_restore_unit "${unit}"
  done

  restore_processes "${process_state}"
  if [[ "${deferred_timer}" == "true" ]]; then
    start_restore_unit hyprpaper-slideshow.timer
  fi

  if [[ "${rgb_profile_saved}" == "true" && -s "${RGB_PROFILE}" ]]; then
    if ! timeout 30s openrgb --profile "${RGB_PROFILE}" --noautoconnect >/dev/null 2>&1; then
      error "failed to restore the OpenRGB profile"
    fi
  fi

  if [[ "${suspend_state}" == "true" ]]; then
    : > "${SUSPEND_STATE_FILE}"
  else
    rm -f "${SUSPEND_STATE_FILE}"
  fi

  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl dispatch 'hl.dsp.dpms({ action = "on" })' >/dev/null 2>&1 || error "failed to power on the displays"
  fi

  current_errors="$(errors_json)"
  temp_file="$(mktemp "${STATE_DIR}/state.json.tmp.XXXXXX")" || return 1
  if (( ${#errors[@]} == 0 )); then
    jq --arg restoredAt "$(date --iso-8601=seconds)" \
      '.active = false | .phase = "off" | .restoredAt = $restoredAt | .errors = []' \
      "${STATE_FILE}" > "${temp_file}"
  else
    jq --argjson errors "${current_errors}" \
      '.active = true | .phase = "restore-failed" | .errors = $errors' \
      "${STATE_FILE}" > "${temp_file}"
  fi
  mv "${temp_file}" "${STATE_FILE}"

  if (( ${#errors[@]} > 0 )); then
    printf 'Away mode restore needs attention:\n' >&2
    printf '  - %s\n' "${errors[@]}" >&2
    return 1
  fi

  printf 'Away mode is off: the recorded services, processes, RGB profile, and displays were restored.\n'
  printf 'The session remains locked; authenticate normally to continue.\n'
}

away_mode_status() {
  local active=false phase=off tailscale_online=false ssh_ready=false codex_ready=false
  local monitors_off=false managed_active=0 unit rgb_profile_saved=false

  if state_is_active; then
    active=true
    phase="$(jq -r '.phase // "active"' "${STATE_FILE}")"
    rgb_profile_saved="$(jq -r '.rgbProfileSaved // false' "${STATE_FILE}")"
  elif [[ -f "${STATE_FILE}" ]]; then
    phase="$(jq -r '.phase // "off"' "${STATE_FILE}" 2>/dev/null || printf off)"
    rgb_profile_saved="$(jq -r '.rgbProfileSaved // false' "${STATE_FILE}" 2>/dev/null || printf false)"
  fi

  if tailscale status --json 2>/dev/null |
      jq -e '.BackendState == "Running" and .Self.Online == true' >/dev/null; then
    tailscale_online=true
  fi
  if systemctl is-active --quiet sshd.service &&
      ss -H -lnt 'sport = :22' 2>/dev/null | grep -q .; then
    ssh_ready=true
  fi
  if systemctl --user is-active --quiet codex-remote-control.service &&
      pgrep -f '[c]odex app-server --remote-control' >/dev/null; then
    codex_ready=true
  fi
  if command -v hyprctl >/dev/null 2>&1 &&
      hyprctl monitors -j 2>/dev/null | jq -e 'length > 0 and all(.[]; .dpmsStatus == false)' >/dev/null; then
    monitors_off=true
  fi
  for unit in "${MANAGED_UNITS[@]}"; do
    systemctl --user is-active --quiet "${unit}" 2>/dev/null && (( managed_active += 1 ))
  done

  jq -n \
    --argjson active "${active}" \
    --arg phase "${phase}" \
    --argjson tailscaleOnline "${tailscale_online}" \
    --argjson sshReady "${ssh_ready}" \
    --argjson codexRemoteReady "${codex_ready}" \
    --argjson monitorsOff "${monitors_off}" \
    --argjson managedUnitsActive "${managed_active}" \
    --argjson rgbProfileSaved "${rgb_profile_saved}" \
    '{active: $active, phase: $phase, tailscaleOnline: $tailscaleOnline,
      sshReady: $sshReady, codexRemoteReady: $codexRemoteReady,
      monitorsOff: $monitorsOff, managedUnitsActive: $managedUnitsActive,
      rgbProfileSaved: $rgbProfileSaved}'
}

away_mode_toggle() {
  if state_is_active; then
    away_mode_off
  else
    away_mode_on
  fi
}

case "${1:-}" in
  on) away_mode_on ;;
  off) away_mode_off ;;
  toggle) away_mode_toggle ;;
  status) require_commands && away_mode_status ;;
  verify) require_commands && verify_reachability && printf 'Away-mode reachability prerequisites are healthy.\n' ;;
  *)
    printf 'Usage: %s on|off|toggle|status|verify\n' "$(basename "$0")" >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash

# Inspect live commands owned by coding-agent processes. Selecting a command
# focuses its existing terminal when possible; commands without a terminal get
# a read-only Foot process monitor instead.

set -euo pipefail

agent_commands=(codex opencode claude aider gemini amp)
terminal_commands=(foot kitty alacritty wezterm ghostty)

agent_kind_for_pid() {
  local pid=$1 comm args kind
  [[ -r "/proc/$pid/comm" ]] || return 1
  comm=$(<"/proc/$pid/comm")
  args=$(ps -o args= -p "$pid" 2>/dev/null || true)

  for kind in "${agent_commands[@]}"; do
    [[ $comm == "$kind" ]] && {
      printf '%s\n' "$kind"
      return 0
    }
  done

  # Codex Desktop and Remote Control launch tool shells beneath these hosts.
  case "$args" in
    *'/codex app-server '*|*'/codex-code-mode-host'*)
      printf '%s\n' 'codex-tool'
      return 0
      ;;
  esac
  return 1
}

children_of() {
  local pid=$1 children_file="/proc/$pid/task/$pid/children"
  [[ -r $children_file ]] && cat "$children_file"
}

descendants_of() {
  local pid=$1 child
  for child in $(children_of "$pid"); do
    printf '%s\n' "$child"
    descendants_of "$child"
  done
}

is_interactive_shell() {
  local pid=$1 comm args
  [[ -r "/proc/$pid/comm" ]] || return 1
  comm=$(<"/proc/$pid/comm")
  case "$comm" in
    bash|zsh|sh|fish)
      args=$(ps -o args= -p "$pid" 2>/dev/null || true)
      case " $args " in
        *' -c '*|*' -lc '*|*' -ic '*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

terminal_window_for_pid() {
  local pid=$1 comm parent address terminal
  while [[ $pid =~ ^[0-9]+$ && $pid -gt 1 && -r "/proc/$pid/comm" ]]; do
    comm=$(<"/proc/$pid/comm")
    for terminal in "${terminal_commands[@]}"; do
      if [[ $comm == "$terminal" ]]; then
        address=$(hyprctl clients -j 2>/dev/null | jq -r --argjson pid "$pid" \
          '.[] | select(.mapped and .pid == $pid) | .address' | head -n 1)
        [[ -n $address ]] && {
          printf '%s\n' "$address"
          return 0
        }
      fi
    done
    parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ $parent =~ ^[0-9]+$ ]] || break
    pid=$parent
  done
  return 1
}

command_text() {
  local pid=$1 command
  command=$(ps -o args= -p "$pid" 2>/dev/null || true)
  command=${command//$'\t'/ }
  command=${command//$'\n'/ }
  printf '%.180s\n' "$command"
}

display_agent_kind() {
  case "$1" in
    codex-tool) printf '%s\n' 'codex tool runner' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

emit_entry() {
  local agent=$1 owner_pid=$2 pid=$3 command address action cwd label
  [[ -d "/proc/$pid" ]] || return 0
  is_interactive_shell "$pid" && return 0
  command=$(command_text "$pid")
  [[ -n $command ]] || return 0
  label="[$(display_agent_kind "$agent"):$owner_pid] PID $pid  $command"
  if address=$(terminal_window_for_pid "$pid"); then
    action="focus:$address"
    label+="  (existing terminal)"
  else
    action="watch:$pid:$agent"
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || printf '?')
    cwd=${cwd//$'\t'/ }
    cwd=${cwd//$'\n'/ }
    label+="  (hidden, $cwd)"
  fi
  printf '%s\t%s\n' "$action" "$label"
}

watch_command() {
  local pid=${2:?missing PID} agent=${3:?missing agent name}
  local title="[$(display_agent_kind "$agent")] PID $pid"
  clear
  printf '%s\n\n' "$title"
  printf '%s\n' 'Read-only live process monitor. Ctrl+C closes this Foot window.'
  while kill -0 "$pid" 2>/dev/null; do
    printf '\033[H\033[2J%s\n\n' "$title"
    ps -o pid=,ppid=,tty=,stat=,etime=,args= -p "$pid" 2>/dev/null || true
    printf '\nProcess tree:\n'
    pstree -ap "$pid" 2>/dev/null || true
    sleep 1
  done
  printf '\nCommand has exited. Press Enter to close.\n'
  read -r _ || true
}

show_menu() {
  local proc_root pid agent selected action address watch_pid watch_agent
  local -a roots=()

  while IFS= read -r proc_root; do
    agent=$(agent_kind_for_pid "$proc_root" || true)
    [[ -n $agent ]] && roots+=("$agent:$proc_root")
  done < <(find /proc -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort -n)

  selected=$(
    {
      for entry in "${roots[@]}"; do
        agent=${entry%%:*}
        pid=${entry##*:}
        emit_entry "$agent" "$pid" "$pid"
        while IFS= read -r proc_root; do
          emit_entry "$agent" "$pid" "$proc_root"
        done < <(descendants_of "$pid")
      done
    } | sort -u | fuzzel \
      --dmenu \
      --no-run-if-empty \
      --only-match \
      --prompt 'Agent commands> ' \
      --with-nth=2.. \
      --accept-nth=1
  ) || return 0

  [[ -n $selected ]] || return 0
  case "$selected" in
    focus:*)
      address=${selected#focus:}
      hyprctl dispatch "hl.dsp.focus({ window = 'address:$address' })" >/dev/null
      ;;
    watch:*)
      watch_pid=${selected#watch:}
      watch_agent=${watch_pid#*:}
      watch_pid=${watch_pid%%:*}
      exec foot --app-id=agent-command-monitor --title "Agent command: $watch_agent" \
        -e "$0" --watch "$watch_pid" "$watch_agent"
      ;;
  esac
}

case "${1:-}" in
  --watch) watch_command "$@" ;;
  '') show_menu ;;
  *) printf 'Usage: %s [--watch PID AGENT]\n' "$0" >&2; exit 2 ;;
esac

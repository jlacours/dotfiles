#!/usr/bin/env bash
# hypridle-video-inhibit — keep monitors awake only while a fullscreen window
# (i.e. a video you're actually watching) is visible; let audio-only playback idle.
#
# Why this exists:
#   hypridle has only a global `ignore_dbus_inhibit` switch — it can't tell Firefox/Zen's
#   "Playing audio" idle-inhibit from "Playing video". So we set ignore_dbus_inhibit = true
#   (hypridle ignores ALL browser screensaver locks, audio AND video) and re-add an idle
#   lock ourselves, but only when a fullscreen window is on a visible workspace. hypridle
#   still honors systemd idle locks (ignore_systemd_inhibit stays false), so this works.
#
# Heuristic: "watching video" ≈ "something is fullscreen". Background music/podcasts run
# windowed and will let the screens blank after hypridle's normal 15-min timeout.
#
# Wired up as the user service hypridle-video-inhibit.service (graphical-session.target).

set -uo pipefail

POLL=5  # seconds between fullscreen checks (idle is a 15-min affair; this is plenty)

# hyprctl needs the instance signature. It's normally in the service env, but fall back to
# the most recently created instance dir under $XDG_RUNTIME_DIR/hypr just in case.
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export HYPRLAND_INSTANCE_SIGNATURE="${HYPRLAND_INSTANCE_SIGNATURE:-$(ls -t "$runtime/hypr" 2>/dev/null | head -1)}"

lock_pid=""

release() {
    if [[ -n "$lock_pid" ]]; then
        kill "$lock_pid" 2>/dev/null
        lock_pid=""
    fi
}
trap 'release; exit 0' EXIT INT TERM

# True if any monitor's currently-active workspace contains a fullscreen window.
# (Covers fullscreen video on a non-focused monitor — this is a multi-head setup.)
fullscreen_visible() {
    local active fs
    active=$(hyprctl monitors -j 2>/dev/null | jq -c '[.[].activeWorkspace.id]') || return 1
    fs=$(hyprctl workspaces -j 2>/dev/null \
        | jq --argjson a "$active" 'any(.[]; .hasfullscreen and (.id | IN($a[])))') || return 1
    [[ "$fs" == "true" ]]
}

while true; do
    if fullscreen_visible; then
        if [[ -z "$lock_pid" ]]; then
            systemd-inhibit --what=idle --mode=block \
                --who="hypridle-video-inhibit" --why="Fullscreen video playing" \
                sleep infinity &
            lock_pid=$!
            echo "[video-inhibit] HELD idle lock — fullscreen window visible"
        fi
    else
        if [[ -n "$lock_pid" ]]; then
            release
            echo "[video-inhibit] RELEASED idle lock — no fullscreen window"
        fi
    fi
    sleep "$POLL"
done

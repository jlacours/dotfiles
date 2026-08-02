#!/usr/bin/env bash
# Change the default sink volume, then replace the previous volume notification.
set -euo pipefail

sink='@DEFAULT_AUDIO_SINK@'
runtime_dir=${XDG_RUNTIME_DIR:-"/run/user/$(id -u)"}
notification_id_file="$runtime_dir/volume-notification-id"

# Keep rapid media-key presses ordered, and replace mako's server-assigned ID.
exec 9>"$runtime_dir/volume-notification.lock"
flock 9

notify_volume() {
    local -a args=(-a 'Volume' -p -t 1500)
    local notification_id

    if [[ -r $notification_id_file ]]; then
        notification_id=$(<"$notification_id_file")
        if [[ $notification_id =~ ^[0-9]+$ ]]; then
            args+=(-r "$notification_id")
        fi
    fi

    notification_id=$(notify-send "${args[@]}" "$@")
    printf '%s\n' "$notification_id" > "$notification_id_file"
}

case "${1:-}" in
    up)
        wpctl set-volume -l 1.0 "$sink" 1%+
        ;;
    down)
        wpctl set-volume "$sink" 1%-
        ;;
    mute)
        wpctl set-mute "$sink" toggle
        ;;
    *)
        printf 'Usage: %s {up|down|mute}\n' "${0##*/}" >&2
        exit 64
        ;;
esac

status=$(wpctl get-volume "$sink")
if [[ $status == *MUTED* ]]; then
    notify_volume 'Volume muted'
    exit 0
fi

volume=$(awk '{printf "%.0f", $2 * 100}' <<<"$status")
notify_volume 'Volume' "${volume}%"

#!/usr/bin/env bash

set -u
set -o pipefail

# Screen recording rofi wrapper script
# A multi-level menu interface for wf-recorder
# Supports both Sway and Hyprland

# Configuration
RECORDINGS_DIR="$HOME/Videos/recordings"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell-screenrecord-$UID"
PID_FILE="$STATE_DIR/recorder.pid"
STATUS_FILE="$STATE_DIR/output-file"
CONFIG_FILE="$STATE_DIR/config"
MIX_MODULES_FILE="$STATE_DIR/mix-modules"
LOG_FILE="$STATE_DIR/wf-recorder.log"

# Detect compositor
is_hyprland() {
    [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]
}

# Function to get active window geometry
get_active_window() {
    if is_hyprland; then
        hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"'
    else
        swaymsg -t get_tree | jq -r '.. | select(.focused?) | .rect | "\(.x),\(.y) \(.width)x\(.height)"'
    fi
}

# Function to get the focused output's NAME (for wf-recorder -o).
#
# We capture whole monitors by name, NOT by geometry. hyprctl reports a
# monitor's position in *logical* layout units but its size in *physical*
# pixels, so on a scaled output (e.g. a 4K at scale 1.6) a "\(.x),\(.y)
# \(.width)x\(.height)" rectangle is wrong and wf-recorder either grabs the
# wrong region or falls back to its interactive "select an output" stdin
# prompt — which hangs when launched from the Quickshell menu (no tty).
# `-o <name>` sidesteps all of that and is scale-correct.
get_active_output_name() {
    local name
    if is_hyprland; then
        name=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
        [ -z "$name" ] && name=$(hyprctl monitors -j | jq -r '.[0].name // empty')
    else
        name=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name')
        [ -z "$name" ] && name=$(swaymsg -t get_outputs | jq -r '.[0].name // empty')
    fi
    echo "$name"
}

# Quality presets for wf-recorder's default libx264 encoder.
# wf-recorder forwards these with `-p`; FFmpeg-style `-b:v` is not valid here.
declare -A QUALITY_PRESETS
QUALITY_PRESETS[low]="crf=28"
QUALITY_PRESETS[medium]="crf=23"
QUALITY_PRESETS[high]="crf=18"
QUALITY_PRESETS[ultra]="crf=14"

# Runtime state is private to this login session and user.
mkdir -p "$RECORDINGS_DIR"
install -d -m 700 "$STATE_DIR"

recorder_pid_is_ours() {
    local pid=$1
    local command_name

    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    command_name=$(ps -p "$pid" -o comm= 2>/dev/null) || return 1
    [ "$command_name" = "wf-recorder" ]
}

cleanup_audio_mix() {
    local -a module_ids=()
    local index

    if [ -f "$MIX_MODULES_FILE" ]; then
        mapfile -t module_ids < "$MIX_MODULES_FILE"
        for ((index=${#module_ids[@]} - 1; index >= 0; index--)); do
            pactl unload-module "${module_ids[index]}" >/dev/null 2>&1 || true
        done
        rm -f "$MIX_MODULES_FILE"
    fi
}

clear_runtime_state() {
    rm -f "$PID_FILE" "$STATUS_FILE" "$CONFIG_FILE"
}

# Function to check if wf-recorder is running
is_recording() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if recorder_pid_is_ours "$pid"; then
            return 0
        fi

        cleanup_audio_mix
        clear_runtime_state
    fi
    return 1
}

# Function to show the quickshell dmenu overlay and get selection
# $1 = prompt text
# $2 = options (newline-separated string)
show_menu() {
    local prompt=$1
    local options=$2
    # -i: case insensitive (accepted, always on)
    # -p: prompt text
    # -no-custom: only allow selecting from list, no custom input
    printf '%b\n' "$options" | "$HOME/.config/quickshell/scripts/qs-dmenu.sh" -i -p "$prompt" -no-custom
}

# Function to select recording area
select_area() {
    local area=$1
    local output_name=""
    local geometry=""
    case $area in
        "Active output")
            # Emit an OUTPUT:<name> sentinel so start_recording uses
            # `wf-recorder -o` (scale-safe and non-interactive).
            output_name=$(get_active_output_name)
            if [ -n "$output_name" ]; then
                echo "OUTPUT:$output_name"
            else
                echo "CANCEL"
            fi
            ;;
        "Active window")
            geometry=$(get_active_window)
            if [ -n "$geometry" ]; then
                echo "$geometry"
            else
                echo "CANCEL"
            fi
            ;;
        "Select region")
            geometry=$(slurp -d \
                -b '#00000066' \
                -c '#ffcc00ff' \
                -s '#ffcc0033' \
                -w 3 </dev/null 2>/dev/null)
            if [ -n "$geometry" ]; then
                echo "$geometry"
            else
                echo "CANCEL"
            fi
            ;;
        *)
            echo "CANCEL"
            ;;
    esac
}

# Function to select audio input
select_audio() {
    local audio=$1
    case $audio in
        "No audio")
            echo "none"
            ;;
        "System audio")
            echo "system"
            ;;
        "Microphone")
            echo "mic"
            ;;
        "System + Microphone")
            echo "both"
            ;;
        *)
            echo "CANCEL"
            ;;
    esac
}

# Function to select quality
select_quality() {
    local quality=$1
    case $quality in
        "Low (small file)")
            echo "low"
            ;;
        "Medium (balanced)")
            echo "medium"
            ;;
        "High (large file)")
            echo "high"
            ;;
        "Ultra (very large file)")
            echo "ultra"
            ;;
        *)
            echo "CANCEL"
            ;;
    esac
}

# Function to get microphone device
get_mic_device() {
    local source
    source=$(pactl get-default-source 2>/dev/null || true)

    if [ -n "$source" ] && [[ "$source" != *.monitor ]] \
        && pactl list sources short | awk '{print $2}' | grep -Fxq "$source"; then
        echo "$source"
        return
    fi

    pactl list sources short | awk '$2 !~ /\.monitor$/ {print $2; exit}'
}

# Function to get system audio monitor device
get_system_audio_device() {
    local default_sink
    local monitor_source

    default_sink=$(pactl get-default-sink 2>/dev/null || true)
    monitor_source="${default_sink}.monitor"

    if [ -n "$default_sink" ] \
        && pactl list sources short | awk '{print $2}' | grep -Fxq "$monitor_source"; then
        echo "$monitor_source"
        return
    fi

    pactl list sources short | awk '$2 ~ /\.monitor$/ {print $2; exit}'
}

# Create a private PulseAudio-on-PipeWire sink and loop both sources into it.
# wf-recorder can capture only one source, so the sink monitor is the real mix.
setup_audio_mix() {
    local system_source=$1
    local mic_source=$2
    local sink_name="wf_recorder_mix_${UID}_$$"
    local module_id

    cleanup_audio_mix
    : > "$MIX_MODULES_FILE"

    module_id=$(pactl load-module module-null-sink \
        sink_name="$sink_name" \
        sink_properties=device.description=Screen_Record_Mix) || {
        cleanup_audio_mix
        return 1
    }
    echo "$module_id" >> "$MIX_MODULES_FILE"

    module_id=$(pactl load-module module-loopback \
        source="$system_source" sink="$sink_name" latency_msec=20) || {
        cleanup_audio_mix
        return 1
    }
    echo "$module_id" >> "$MIX_MODULES_FILE"

    module_id=$(pactl load-module module-loopback \
        source="$mic_source" sink="$sink_name" latency_msec=20) || {
        cleanup_audio_mix
        return 1
    }
    echo "$module_id" >> "$MIX_MODULES_FILE"

    echo "${sink_name}.monitor"
}

# Function to start recording with all parameters
start_recording() {
    local geometry=$1
    local audio_mode=$2
    local quality=$3

    local timestamp
    local system_device=""
    local mic_device=""
    local mix_device=""
    local recorder_pid
    timestamp=$(date +%Y%m%d_%H%M%S_%3N)
    local output_file="$RECORDINGS_DIR/recording_${timestamp}.mp4"

    # Build command arguments as array (avoids eval issues with PID tracking)
    local -a cmd_args=()

    # Select what to capture:
    #   OUTPUT:<name> -> a whole monitor via -o (scale-safe, no stdin prompt)
    #   "x,y WxH"     -> a region/window rectangle via -g
    #   empty         -> let wf-recorder pick (single-monitor fallback only)
    if [[ "$geometry" == OUTPUT:* ]]; then
        cmd_args+=(-o "${geometry#OUTPUT:}")
    elif [ -n "$geometry" ]; then
        cmd_args+=(-g "$geometry")
    fi

    # Use wf-recorder's codec-param interface. Its `-b` flag means B-frames,
    # not FFmpeg's `-b:v` bitrate syntax.
    cmd_args+=(-c libx264 -p "${QUALITY_PRESETS[$quality]}")

    # Add audio based on mode
    # wf-recorder uses --audio=<device> format, not separate flags
    case $audio_mode in
        "system")
            system_device=$(get_system_audio_device)
            if [ -n "$system_device" ]; then
                cmd_args+=("--audio=$system_device")
            else
                notify-send -a "Screen Recorder" "Recording failed" "No system-audio monitor source was found"
                return 1
            fi
            ;;
        "mic")
            mic_device=$(get_mic_device)
            if [ -n "$mic_device" ]; then
                cmd_args+=("--audio=$mic_device")
            else
                notify-send -a "Screen Recorder" "Recording failed" "No microphone source was found"
                return 1
            fi
            ;;
        "both")
            system_device=$(get_system_audio_device)
            mic_device=$(get_mic_device)
            if [ -z "$system_device" ] || [ -z "$mic_device" ]; then
                notify-send -a "Screen Recorder" "Recording failed" "System audio and microphone sources are both required"
                return 1
            fi

            mix_device=$(setup_audio_mix "$system_device" "$mic_device") || {
                notify-send -a "Screen Recorder" "Recording failed" "Could not create the temporary audio mix"
                return 1
            }
            cmd_args+=("--audio=$mix_device")
            ;;
    esac

    # Add output file
    cmd_args+=(-f "$output_file")

    # Capture diagnostics instead of leaking stderr into Quickshell. Do not
    # claim success until wf-recorder survives initialization.
    : > "$LOG_FILE"
    wf-recorder "${cmd_args[@]}" > "$LOG_FILE" 2>&1 &
    recorder_pid=$!
    sleep 0.75

    if ! recorder_pid_is_ours "$recorder_pid"; then
        wait "$recorder_pid" 2>/dev/null || true
        cleanup_audio_mix
        rm -f "$output_file"
        notify-send -a "Screen Recorder" "Recording failed" "wf-recorder did not start; see $LOG_FILE"
        return 1
    fi

    printf '%s\n' "$recorder_pid" > "$PID_FILE"
    printf '%s\n' "$output_file" > "$STATUS_FILE"
    printf 'Area: %s, Audio: %s, Quality: %s\n' \
        "$geometry" "$audio_mode" "$quality" > "$CONFIG_FILE"

    notify-send -a "Screen Recorder" "Recording started" "Quality: $quality\nSaving to: $(basename "$output_file")"
}

# Function to stop recording
stop_recording() {
    local pid
    local output_file=""

    if is_recording; then
        pid=$(cat "$PID_FILE")

        # Send SIGINT to wf-recorder (graceful stop to finalize video)
        kill -INT "$pid" 2>/dev/null

        # Wait for process to terminate (up to 10 seconds).
        for _ in {1..20}; do
            if ! recorder_pid_is_ours "$pid"; then
                break
            fi
            sleep 0.5
        done

        # If still running, force kill
        if recorder_pid_is_ours "$pid"; then
            kill -TERM "$pid" 2>/dev/null
            sleep 1
        fi

        # Last resort: SIGKILL
        if recorder_pid_is_ours "$pid"; then
            kill -KILL "$pid" 2>/dev/null
        fi

        cleanup_audio_mix

        if [ -f "$STATUS_FILE" ]; then
            output_file=$(cat "$STATUS_FILE")
        fi

        if [ -n "$output_file" ] && [ -s "$output_file" ]; then
            notify-send -a "Screen Recorder" "Recording stopped" "Saved: $(basename "$output_file")"
        else
            notify-send -a "Screen Recorder" "Recording failed" "No playable output was produced; see $LOG_FILE"
        fi

        clear_runtime_state
    fi
}

# Main menu flow
main() {
    local -a required_commands=(jq notify-send pactl slurp wf-recorder)
    local required_command
    local -a missing_commands=()
    local choice=""
    local area_options area geometry
    local audio_options audio_choice audio_mode
    local quality_options quality_choice quality

    if is_hyprland; then
        required_commands+=(hyprctl)
    else
        required_commands+=(swaymsg)
    fi

    for required_command in "${required_commands[@]}"; do
        command -v "$required_command" >/dev/null 2>&1 \
            || missing_commands+=("$required_command")
    done

    if ((${#missing_commands[@]})); then
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -a "Screen Recorder" "Missing dependencies" "${missing_commands[*]}"
        else
            printf 'screenrecord: missing dependencies: %s\n' "${missing_commands[*]}" >&2
        fi
        exit 1
    fi

    # Check if already recording
    if is_recording; then
        # If recording, offer to stop
        choice=$(show_menu "Recording Active" "Stop recording")
        if [ "$choice" = "Stop recording" ]; then
            stop_recording
        fi
        exit 0
    fi
    
    # Step 1: Select area
    area_options="Active output\nActive window\nSelect region"
    area=$(show_menu "Select Area" "$area_options")
    
    # Check for cancellation (empty selection)
    # -z tests if string is empty
    if [ -z "$area" ]; then
        exit 0
    fi
    
    geometry=$(select_area "$area")
    if [ "$geometry" = "CANCEL" ]; then
        notify-send -a "Screen Recorder" "Recording cancelled" "No region selected"
        exit 0
    fi
    
    # Step 2: Select audio
    audio_options="No audio\nSystem audio\nMicrophone\nSystem + Microphone"
    audio_choice=$(show_menu "Select Audio" "$audio_options")
    
    if [ -z "$audio_choice" ]; then
        exit 0
    fi
    
    audio_mode=$(select_audio "$audio_choice")
    if [ "$audio_mode" = "CANCEL" ]; then
        exit 0
    fi
    
    # Step 3: Select quality
    quality_options="Low (small file)\nMedium (balanced)\nHigh (large file)\nUltra (very large file)"
    quality_choice=$(show_menu "Select Quality" "$quality_options")
    
    if [ -z "$quality_choice" ]; then
        exit 0
    fi
    
    quality=$(select_quality "$quality_choice")
    if [ "$quality" = "CANCEL" ]; then
        exit 0
    fi
    
    # Start recording with all selected parameters
    start_recording "$geometry" "$audio_mode" "$quality"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main
fi

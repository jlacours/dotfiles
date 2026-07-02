#!/usr/bin/env bash
# JuBotAI quickshell module: status + toggle for the Discord bot AND its
# llama-server brain. On toggle, spawns two named foot windows (one for
# llama-choose, one for bot.py). Toggle-off kills both and closes the windows.

set -uo pipefail

BOT_DIR="$HOME/Projects/JuBotAI"
BOT_CMD_MATCH='\.venv/bin/python -u bot\.py'
LLAMA_BIN=llama-server
LLAMA_PORT=3002
FOOT_LLAMA_APPID=jubotai-llama
FOOT_BOT_APPID=jubotai-bot

bot_pid()   { pgrep -f "$BOT_CMD_MATCH" | head -n1; }
llama_pid() { pgrep -x "$LLAMA_BIN"      | head -n1; }

status() {
    local b l class text tooltip
    b=$(bot_pid)
    l=$(llama_pid)

    if [[ -n "$b" && -n "$l" ]]; then
        class=jubotai-on
        text=ON
        tooltip="JuBotAI ON | bot pid $b | llama pid $l"
    elif [[ -n "$b" || -n "$l" ]]; then
        class=jubotai-partial
        text=HALF
        tooltip="JuBotAI partial | bot=${b:-off} | llama=${l:-off}"
    else
        class=jubotai-off
        text=OFF
        tooltip="JuBotAI is off — click to start"
    fi

    jq --unbuffered --compact-output -n \
        --arg text "$text" \
        --arg class "$class" \
        --arg tooltip "$tooltip" \
        '{text: $text, alt: "󰚩", class: $class, tooltip: $tooltip}'
}

start() {
    foot --app-id="$FOOT_LLAMA_APPID" --title="jubotai-llama" \
          --hold -e bash -lc 'export PATH="$HOME/.local/bin:$HOME/repos/llama.cpp/build/bin:$PATH"; exec llama-choose' >/dev/null 2>&1 &
    disown
    foot --app-id="$FOOT_BOT_APPID" --title="jubotai-bot" \
          --hold -e bash -lc "
              cd '$BOT_DIR' || exit 1
              for i in {1..60}; do
                  if ss -tln 2>/dev/null | grep -q ':${LLAMA_PORT}'; then break; fi
                  echo \"[jubotai-toggle] waiting for llama-server on :${LLAMA_PORT} (\$i/60)\"
                  sleep 1
              done
              exec .venv/bin/python -u bot.py
          " >/dev/null 2>&1 &
    disown
}

stop() {
    local b l
    b=$(bot_pid)
    l=$(llama_pid)
    [[ -n "$b" ]] && kill "$b" 2>/dev/null
    [[ -n "$l" ]] && kill "$l" 2>/dev/null
    sleep 1
    b=$(bot_pid);   [[ -n "$b" ]] && kill -9 "$b" 2>/dev/null
    l=$(llama_pid); [[ -n "$l" ]] && kill -9 "$l" 2>/dev/null
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch closewindow "class:^${FOOT_LLAMA_APPID}$" >/dev/null 2>&1
        hyprctl dispatch closewindow "class:^${FOOT_BOT_APPID}$"   >/dev/null 2>&1
    fi
}

toggle() {
    if [[ -n "$(bot_pid)" || -n "$(llama_pid)" ]]; then
        stop
    else
        start
    fi
}

case "${1:-status}" in
    toggle) toggle ;;
    start)  start ;;
    stop)   stop ;;
    *)      status ;;
esac

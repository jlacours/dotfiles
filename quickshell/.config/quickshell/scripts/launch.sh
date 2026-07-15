#!/usr/bin/env bash

set -euo pipefail

# Qt 6 may try to register the same portal app connection twice for this
# layer-shell process. It is harmless, but it pollutes Quickshell logs.
if [[ -n "${QT_LOGGING_RULES:-}" ]]; then
  export QT_LOGGING_RULES="${QT_LOGGING_RULES};qt.qpa.services.warning=false"
else
  export QT_LOGGING_RULES="qt.qpa.services.warning=false"
fi

# Live variants: square (wallust rice, top bar) and win95 (retro taskbar,
# bottom). The classic variant remains retired in legacy/quickshell-classic/.
# A root-level shell.qml would disable named configs (-c), so launch by path
# with -p. Config resolution: explicit $1 > state file > square.
state="$HOME/.cache/quickshell-config"

config="${1:-}"
if [[ -z "$config" && -r "$state" ]]; then
  config="$(<"$state")"
fi
config="${config:-square}"

case "$config" in
  square|win95) ;;
  *) config="square" ;;
esac

printf '%s\n' "$config" > "$state"

# Keep Labwc's application theme local even when this launcher is restarted
# from a terminal whose inherited systemd environment still says qt6ct.
if [[ "$config" == "win95" ]]; then
  export GTK_THEME=win95-current
  export QT_QPA_PLATFORMTHEME=gtk3
  export QT_STYLE_OVERRIDE=Windows
fi

exec quickshell -p "$HOME/.config/quickshell/$config" --no-duplicate

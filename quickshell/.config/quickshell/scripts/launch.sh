#!/usr/bin/env bash

set -euo pipefail

# Qt 6 may try to register the same portal app connection twice for this
# layer-shell process. It is harmless, but it pollutes Quickshell logs.
if [[ -n "${QT_LOGGING_RULES:-}" ]]; then
  export QT_LOGGING_RULES="${QT_LOGGING_RULES};qt.qpa.services.warning=false"
else
  export QT_LOGGING_RULES="qt.qpa.services.warning=false"
fi

# square is the sole live variant. The classic variant was retired to
# legacy/quickshell-classic/ (archived, no longer launchable). A root-level
# shell.qml would disable named configs (-c), so launch the square profile by
# path with -p. qs-switch.sh restart relaunches through this script.
exec quickshell -p "$HOME/.config/quickshell/square" --no-duplicate

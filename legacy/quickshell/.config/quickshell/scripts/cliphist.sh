#!/bin/bash

set -euo pipefail

DMENU="$HOME/.config/quickshell/scripts/qs-dmenu.sh"

mapfile -t entries < <(cliphist list | tr -d '\000')

if [[ ${#entries[@]} -eq 0 ]]; then
    exit 0
fi

# Note: the rofi version showed an image preview icon for binary clipboard
# entries; the quickshell overlay is text-only for now (see handoff), so
# binary entries just show their "[[ binary data ... ]]" preview text like
# any other row. This tools-menu entry may also be redundant with the
# always-available clipboard overlay (Super+V, clipboard/ClipboardHistory.qml)
# — kept for parity with the old rofi-tools menu rather than dropped
# unilaterally.
previews=()
for entry in "${entries[@]}"; do
    previews+=("${entry#*$'\t'}")
done

selection="$(printf '%s\n' "${previews[@]}" | "$DMENU" -p "Clipboard History" -i -format i)"

if [[ -z "${selection:-}" ]]; then
    exit 0
fi

printf '%s\n' "${entries[$selection]}" | cliphist decode | wl-copy

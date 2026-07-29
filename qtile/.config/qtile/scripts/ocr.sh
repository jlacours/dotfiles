#!/usr/bin/env bash

# OCR script using grim, slurp, tesseract, and wl-copy
# Select a region on screen and extract text to clipboard

set -euo pipefail

notify() {
    local urgency=$1
    local title=$2
    local body=$3

    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "OCR" -u "$urgency" "$title" "$body" >/dev/null 2>&1 || true
}

die() {
    local message=$1

    printf 'ocr: %s\n' "$message" >&2
    notify critical "OCR failed" "$message"
    exit 1
}

require() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

for dependency in grim slurp tesseract wl-copy; do
    require "$dependency"
done

TMP_IMG=$(mktemp --suffix=.png) || die "Could not create a temporary image"
trap 'rm -f "$TMP_IMG"' EXIT

# Select region and capture screenshot
geometry=$(slurp </dev/null 2>/dev/null) || {
    notify low "OCR cancelled" "No region selected"
    exit 0
}

if [ -z "$geometry" ]; then
    notify low "OCR cancelled" "No region selected"
    exit 0
fi

if ! grim -g "$geometry" "$TMP_IMG" 2>/dev/null; then
    die "Could not capture the selected region"
fi

# Run OCR on the captured image
if ! TEXT=$(tesseract "$TMP_IMG" - 2>/dev/null | sed '/^$/d'); then
    die "Tesseract could not process the captured image"
fi

if [[ -z "$TEXT" ]]; then
    notify normal "OCR" "No text detected"
    exit 0
fi

# Copy to clipboard
if ! printf '%s' "$TEXT" | wl-copy; then
    die "Could not copy the recognized text to the clipboard"
fi

# Show notification with preview of extracted text
PREVIEW="${TEXT:0:100}"
[[ ${#TEXT} -gt 100 ]] && PREVIEW="$PREVIEW..."

notify normal "OCR" $'Copied to clipboard:\n'"$PREVIEW"

#!/bin/sh

# Preserve this session's modes and defaults in the shared helper.
exec "$HOME/.config/session/screenshot.sh" qtile "$@"

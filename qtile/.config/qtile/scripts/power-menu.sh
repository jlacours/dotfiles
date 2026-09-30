#!/bin/sh

# Shared menu with the original session-specific logout action.
exec "$HOME/.config/session/power-menu.sh" qtile "$@"

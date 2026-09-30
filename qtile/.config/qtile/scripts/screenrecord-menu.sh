#!/usr/bin/env bash

# Keep this entrypoint sourceable as well as executable.
source "$HOME/.config/session/screenrecord-menu.sh" qtile "$@"

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main
fi

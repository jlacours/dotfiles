#!/usr/bin/env bash
# Popup rename helper for tmux.
#
# Renaming via the built-in command-prompt draws over the status line, and
# tmux only overwrites the prompt's own width — the rest of the (busy) status
# bar bleeds through, so the old and new states overlap. Running the prompt in
# a display-popup keeps it off the status line entirely.
#
# Usage: rename.sh window|session "<current-name>"

kind=$1
current=$2

read -r -e -i "$current" -p "rename ${kind}: " name
[ -n "$name" ] || exit 0

case $kind in
  window)  tmux rename-window  -- "$name" ;;
  session) tmux rename-session -- "$name" ;;
esac

#!/bin/sh

# Focus a Hyprland client selected through Fuzzel.

set -eu

address=$(
  hyprctl clients -j | jq -r '
    sort_by(.workspace.id, .title)
    | .[]
    | select(.mapped)
    | [.address, ("[" + (.workspace.name // "?") + "]"), (.class // "?"), (.title // "")]
    | @tsv
  ' | fuzzel \
    --dmenu \
    --only-match \
    --prompt "Windows> " \
    --with-nth=2.. \
    --accept-nth=1
) || exit 0

[ -n "$address" ] || exit 0
hyprctl dispatch focuswindow "address:$address" >/dev/null

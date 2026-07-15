#!/usr/bin/env bash
# Apply one coherent Win95 variant to Labwc, GTK, Qt, Wallust, and Quickshell.
set -euo pipefail

home="${HOME:?}"
mode_file="$home/.cache/wallust-current-mode"
theme_dir="$home/.local/share/themes"
current_theme="$theme_dir/win95-current"
requested="${1:-toggle}"

case "$requested" in
  light|dark)
    mode="$requested"
    ;;
  restore)
    mode="light"
    if [[ -r "$mode_file" ]]; then
      cached="$(<"$mode_file")"
      [[ "$cached" == "dark" ]] && mode="dark"
    fi
    ;;
  toggle|"")
    mode="dark"
    if [[ -r "$mode_file" ]] && [[ "$(<"$mode_file")" == "dark" ]]; then
      mode="light"
    fi
    ;;
  *)
    printf 'usage: %s [light|dark|toggle|restore]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

mkdir -p "$theme_dir" "$home/.cache"
if [[ -e "$current_theme" && ! -L "$current_theme" ]]; then
  printf '%s exists and is not a symlink\n' "$current_theme" >&2
  exit 1
fi

# Relative target keeps the theme directory portable. Replace atomically so a
# program starting mid-toggle never sees a missing theme.
ln -sfn "win95-$mode" "$theme_dir/.win95-current.new"
mv -Tf "$theme_dir/.win95-current.new" "$current_theme"

# Wallust still supplies terminal/editor colors. Its generated user GTK CSS
# would override the named Win95 theme, so retire only those two runtime files
# after rendering; Hyprland can regenerate them on its next Wallust change.
wallust cs "win95-$mode" >/dev/null
rm -f "$home/.config/gtk-3.0/gtk.css" "$home/.config/gtk-4.0/gtk.css"

printf 'win95-%s\n' "$mode" > "$home/.cache/wallust-current-theme"
printf '%s\n' "$mode" > "$mode_file"

if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface gtk-theme win95-current
  if [[ "$mode" == "dark" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
  else
    gsettings set org.gnome.desktop.interface color-scheme default
  fi
fi

labwc --reconfigure >/dev/null 2>&1 || true

if [[ "$requested" != "restore" ]] && pgrep -x quickshell >/dev/null; then
  setsid -f "$home/.config/quickshell/scripts/qs-switch.sh" restart \
    >/dev/null 2>&1 || true
fi

printf 'win95-%s applied\n' "$mode"

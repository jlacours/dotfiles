#!/usr/bin/env bash
# Force already-running GTK3/GTK4 apps to re-read ~/.config/gtk-*/gtk.css after
# wallust regenerates it.
#
# GTK only re-parses the user gtk.css when the *theme* setting changes, so we
# briefly flip gtk-theme to a throwaway value and flip it straight back. On
# Wayland/Hyprland, GTK apps watch the org.gnome.desktop.interface GSettings
# keys directly, so this nudge reaches them without any xsettings daemon.
set -euo pipefail

command -v gsettings >/dev/null 2>&1 || exit 0

iface="org.gnome.desktop.interface"
current="$(gsettings get "$iface" gtk-theme 2>/dev/null | tr -d "\"'")"
[[ -n "$current" ]] || current="Adwaita-dark"

# Flip to a *different* real theme, then back — that delta is what triggers the
# reparse. Adwaita ships with GTK so it always exists.
nudge="Adwaita"
[[ "$current" == "Adwaita" ]] && nudge="Adwaita-dark"

gsettings set "$iface" gtk-theme "$nudge"
# tiny gap so the change signal is delivered before we flip back
sleep 0.15
gsettings set "$iface" gtk-theme "$current"

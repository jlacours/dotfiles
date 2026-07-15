#!/bin/sh

# The systemd user manager can outlive a compositor session. Restart shared
# display-bound services after the new compositor has imported its environment,
# so no backend or numbered Wayland socket leaks across sessions.
portal_units="xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-wlr.service"

systemctl --user stop $portal_units >/dev/null 2>&1 || true
systemctl --user reset-failed $portal_units polkit-kde-agent.service \
    >/dev/null 2>&1 || true
systemctl --user --no-block start xdg-desktop-portal.service
systemctl --user --no-block restart polkit-kde-agent.service

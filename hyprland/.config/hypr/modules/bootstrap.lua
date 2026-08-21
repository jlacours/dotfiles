-- Bootstrap configuration for the Hyprland Lua migration.
-- The main hyprland.lua will require this module after the full translation
-- has been reviewed. Until then, the legacy hyprland.conf remains active.

local terminal = "footclient"

local programs = {
  terminal = terminal,
  file_manager = terminal .. " -e ranger",
  alternate_file_manager = "pcmanfm",
  menu = "fuzzel",
  web_browser = "helium-browser",
  alternate_web_browser = "librewolf",
  dropdown_terminal = terminal .. " --app-id=scratchpad -o colors-dark.alpha=0.9 -e zsh",
  newsboat = terminal .. " --app-id=newsboat -e newsboat",
  power_menu = "~/.config/hypr/scripts/power-menu.sh",
  window_menu = "~/.config/hypr/scripts/window-menu.sh",
  music_player = terminal .. " -e rmpc",
  restart_bar = [[sh -c "qs -c hyprbar kill >/dev/null 2>&1 || true; exec qs -c hyprbar -d"]],
  tools_menu = "~/.local/bin/fuzzel-tools",
  apps_menu = "~/.local/bin/fuzzel-apps",
  screen_menu = "~/.config/hypr/scripts/screens-menu.sh",
  emacs_client = "emacsclient -c",
  nvim = terminal .. " --app-id=nvim -e nvim",
  pulsemixer = terminal .. " --app-id=pulsemixer -e pulsemixer",
}

-- Two vertically stacked 1080p displays: 24in above, 27in below.
hl.monitor({
  output = "DP-1",
  mode = "1920x1080@100",
  position = "0x0",
  scale = 1,
})

hl.monitor({
  output = "HDMI-A-1",
  mode = "1920x1080@74.97300",
  position = "0x1080",
  scale = 1,
})

for workspace = 1, 5 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = "HDMI-A-1",
    default = workspace == 1,
  })
end

for workspace = 6, 10 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = "DP-1",
    default = workspace == 6,
  })
end

-- Autostart: Lua gives each command a normal string and starts it
-- asynchronously. No trailing '&' or 'disown' is needed.
hl.on("hyprland.start", function()
  hl.exec_cmd("~/.config/session/reset-display-services.sh")
  hl.exec_cmd("hyprpaper")
  hl.exec_cmd("qs -c hyprbar -d")
  hl.exec_cmd("wl-paste --watch cliphist store")
  hl.exec_cmd(programs.dropdown_terminal)
  hl.exec_cmd("sleep 5 && paplay ~/.config/hypr/greeting.wav")

  -- The legacy '[workspace special:magic silent]' prefix becomes an exec
  -- rule. The silent behavior will be verified when this module is live.
  hl.exec_cmd(
    programs.terminal .. " --app-id=calcurse -e calcurse-sync",
    { workspace = "special:magic" }
  )
end)

-- Environment variables are now explicit function calls.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Permissions are structured data instead of comma-separated directives.
hl.permission({
  binary = "/usr/(bin|local/bin)/grim",
  type = "screencopy",
  mode = "allow",
})

hl.permission({
  binary = "/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland",
  type = "screencopy",
  mode = "allow",
})

return programs

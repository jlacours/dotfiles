-- Full keybinding translation from the legacy bindd/bindde/binddr/binddm set.
--
-- The small helpers keep the repetitive parts readable while still leaving
-- every shortcut discoverable in hyprctl binds and the keybindings menu.

local programs = require("modules/bootstrap")
local main_mod = "SUPER"
local workspace_groups = require("modules/workspaces")

local function bind(keys, action, description, options)
  options = options or {}
  if description then
    options.description = description
  end
  hl.bind(keys, action, options)
end

local function exec(keys, command, description, options)
  bind(keys, hl.dsp.exec_cmd(command), description, options)
end

local function dispatch(keys, action, description, options)
  bind(keys, action, description, options)
end

-- In a Lua-configured session, hyprctl dispatch expects a Lua dispatcher
-- expression. The minimal active bar has no workspace-flash IPC handler, so
-- perform focus changes natively without sending a guaranteed-to-fail call.
local function focus_with_workspace_flash(keys, focus, description)
  bind(keys, function()
    hl.dispatch(hl.dsp.focus(focus))
  end, description)
end

local function set_zoom_mode(factor, submap)
  return function()
    hl.config({ cursor = { zoom_factor = factor } })
    hl.dispatch(hl.dsp.submap(submap))
  end
end

-- Launchers
exec(main_mod .. " + return", programs.terminal, "Open terminal")
exec(main_mod .. " + SHIFT + return", programs.dropdown_terminal, "Open dropdown terminal")
exec(main_mod .. " + D", programs.menu, "App launcher")
exec(main_mod .. " + E", programs.file_manager, "File manager")
exec(main_mod .. " + SHIFT + E", programs.alternate_file_manager, "GUI file manager")
exec(main_mod .. " + A", programs.emacs_client, "Emacs")
exec(main_mod .. " + SHIFT + A", programs.nvim, "Neovim")
exec(main_mod .. " + W", programs.web_browser, "Web browser")
exec(main_mod .. " + SHIFT + W", programs.alternate_web_browser, "Alt. Web Browser")
exec(main_mod .. " + B", programs.apps_menu, "Favorite apps menu")
exec(main_mod .. " + tab", programs.window_menu, "Window switcher")
exec(main_mod .. " + F1", "~/.config/hypr/scripts/keybinds-menu.sh", "Show keybindings")
exec(main_mod .. " + F2", programs.agent_command_menu, "Show live agent commands")

-- Window actions
dispatch(main_mod .. " + Q", hl.dsp.window.close(), "Close active window")
dispatch(main_mod .. " + SHIFT + F", hl.dsp.window.float(), "Toggle floating")
dispatch(main_mod .. " + F", hl.dsp.window.fullscreen(), "Toggle fullscreen")
dispatch(main_mod .. " + P", hl.dsp.window.pin(), "Pin window")
dispatch(main_mod .. " + SHIFT + C", hl.dsp.window.center(), "Center floating window")
dispatch(main_mod .. " + G", hl.dsp.group.toggle(), "Toggle tab group")
dispatch(main_mod .. " + SHIFT + G", hl.dsp.window.move({ out_of_group = true }), "Move out of tab group")
dispatch(main_mod .. " + bracketleft", hl.dsp.group.prev(), "Previous tab")
dispatch(main_mod .. " + bracketright", hl.dsp.group.next(), "Next tab")

-- Bars and overlays
exec(
  main_mod .. " + N",
  "makoctl dismiss --all",
  "Dismiss notifications"
)
exec(main_mod .. " + CTRL + SHIFT + slash", programs.restart_bar, "Restart bar")

-- Theme
exec(main_mod .. " + SHIFT + slash", programs.restart_bar, "Restart bar")
exec(main_mod .. " + SHIFT + semicolon", "~/.local/bin/wallust-random-light", "Random light theme")

-- Audio
exec(main_mod .. " + M", "~/.config/hypr/scripts/volume-notify.sh mute", "Toggle mute")
exec(main_mod .. " + SHIFT + M", programs.pulsemixer, "Pulsemixer")
exec(main_mod .. " + CTRL + M", "~/.local/bin/cycle-sink", "Cycle audio output")

-- Hardware media keys
exec("XF86AudioRaiseVolume", "~/.config/hypr/scripts/volume-notify.sh up", "Volume up (media key)")
exec("XF86AudioLowerVolume", "~/.config/hypr/scripts/volume-notify.sh down", "Volume down (media key)")
exec("XF86AudioMute", "~/.config/hypr/scripts/volume-notify.sh mute", "Toggle mute (media key)")

-- Layout
dispatch(main_mod .. " + O", hl.dsp.layout("orientationcycle left top right bottom center"), "Cycle layout orientation")
exec(main_mod .. " + grave", "~/.config/hypr/scripts/cycle-layout.sh", "Cycle layout")
dispatch(main_mod .. " + SHIFT + bracketright", hl.dsp.layout("rollnext"), "Roll stack next")
dispatch(main_mod .. " + SHIFT + bracketleft", hl.dsp.layout("rollprev"), "Roll stack prev")
dispatch(main_mod .. " + comma", hl.dsp.layout("colresize -conf"), "Shrink column (preset)")
dispatch(main_mod .. " + period", hl.dsp.layout("colresize +conf"), "Grow column (preset)")
dispatch(main_mod .. " + T", hl.dsp.layout("fit active"), "Fit active column")
dispatch(main_mod .. " + SHIFT + T", hl.dsp.layout("fit all"), "Fit all columns")
dispatch(main_mod .. " + CTRL + T", hl.dsp.layout("fit visible"), "Fit visible columns")
dispatch(main_mod .. " + ALT + LEFT", hl.dsp.layout("move -col"), "Scroll camera left")
dispatch(main_mod .. " + ALT + RIGHT", hl.dsp.layout("move +col"), "Scroll camera right")
dispatch(main_mod .. " + ALT + H", hl.dsp.layout("move -col"), "Scroll camera left (Vim)")
dispatch(main_mod .. " + ALT + L", hl.dsp.layout("move +col"), "Scroll camera right (Vim)")
dispatch(main_mod .. " + SHIFT + P", hl.dsp.layout("promote"), "Promote to own column")
dispatch(main_mod .. " + CTRL + SHIFT + LEFT", hl.dsp.layout("swapcol l"), "Swap column left")
dispatch(main_mod .. " + CTRL + SHIFT + RIGHT", hl.dsp.layout("swapcol r"), "Swap column right")
dispatch(main_mod .. " + CTRL + SHIFT + H", hl.dsp.layout("swapcol l"), "Swap column left (Vim)")
dispatch(main_mod .. " + CTRL + SHIFT + L", hl.dsp.layout("swapcol r"), "Swap column right (Vim)")

-- Menus and utilities
exec(main_mod .. " + SHIFT + Q", programs.power_menu, "Power menu")
bind(main_mod .. " + F12", function()
  hl.dispatch(hl.dsp.dpms({ action = "on" }))
  hl.exec_cmd("loginctl lock-session")
end, "Lock screen")
exec(main_mod .. " + ALT + G", "~/.config/hypr/scripts/game-mode.sh toggle", "Toggle game mode")
exec(main_mod .. " + SHIFT + F12", programs.screen_menu, "Deactivate screens")
exec(main_mod .. " + S", programs.tools_menu, "Tools menu")
exec(main_mod .. " + V", "~/.config/hypr/scripts/cliphist-menu.sh", "Clipboard history")
exec(main_mod .. " + I", "~/.config/session/idle-inhibit.sh toggle", "Toggle idle inhibitor")

-- Navigation. The active minimal bar does not provide a workspace-flash IPC
-- endpoint, so these bindings only perform the focus operation.
for _, item in ipairs({
  { key = "LEFT", direction = "l", description = "Focus left" },
  { key = "RIGHT", direction = "r", description = "Focus right" },
  { key = "UP", direction = "u", description = "Focus up" },
  { key = "DOWN", direction = "d", description = "Focus down" },
  { key = "H", direction = "l", description = "Focus left (Vim)" },
  { key = "L", direction = "r", description = "Focus right (Vim)" },
  { key = "K", direction = "u", description = "Focus up (Vim)" },
  { key = "J", direction = "d", description = "Focus down (Vim)" },
}) do
  focus_with_workspace_flash(
    main_mod .. " + " .. item.key,
    { direction = item.direction },
    item.description
  )
end
dispatch(main_mod .. " + U", hl.dsp.focus({ urgent_or_last = true }), "Focus urgent or last window")

-- Moving windows
for _, item in ipairs({
  { key = "LEFT", direction = "l", description = "Move window left" },
  { key = "DOWN", direction = "d", description = "Move window down" },
  { key = "UP", direction = "u", description = "Move window up" },
  { key = "RIGHT", direction = "r", description = "Move window right" },
  { key = "H", direction = "l", description = "Move window left (Vim)" },
  { key = "J", direction = "d", description = "Move window down (Vim)" },
  { key = "K", direction = "u", description = "Move window up (Vim)" },
  { key = "L", direction = "r", description = "Move window right (Vim)" },
}) do
  dispatch(
    main_mod .. " + SHIFT + " .. item.key,
    hl.dsp.window.move({ direction = item.direction }),
    item.description
  )
end

for _, item in ipairs({
  { key = "LEFT", direction = "l", description = "Move into group left" },
  { key = "RIGHT", direction = "r", description = "Move into group right" },
  { key = "UP", direction = "u", description = "Move into group up" },
  { key = "DOWN", direction = "d", description = "Move into group down" },
  { key = "H", direction = "l", description = "Move into group left (Vim)" },
  { key = "L", direction = "r", description = "Move into group right (Vim)" },
  { key = "K", direction = "u", description = "Move into group up (Vim)" },
  { key = "J", direction = "d", description = "Move into group down (Vim)" },
}) do
  dispatch(
    main_mod .. " + CTRL + " .. item.key,
    hl.dsp.window.move({ into_group = item.direction }),
    item.description
  )
end

-- Workspaces. The groups table remains the single source of truth for both
-- workspace rules and the ten regular workspace bindings.
for _, group in ipairs(workspace_groups) do
  for workspace = group.first, group.last do
    local key = tostring(workspace % 10)

    focus_with_workspace_flash(
      main_mod .. " + " .. key,
      { workspace = workspace },
      "Workspace " .. workspace
    )

    dispatch(
      main_mod .. " + SHIFT + " .. key,
      hl.dsp.window.move({ workspace = workspace }),
      "Move window to workspace " .. workspace
    )

    exec(
      main_mod .. " + CTRL + SHIFT + " .. key,
      "~/.config/hypr/scripts/move-workspace-windows.sh " .. workspace,
      "Move all windows to workspace " .. workspace
    )
  end
end

focus_with_workspace_flash(main_mod .. " + Z", { workspace = "m-1" }, "Previous monitor workspace")
focus_with_workspace_flash(main_mod .. " + X", { workspace = "m+1" }, "Next monitor workspace")
focus_with_workspace_flash(main_mod .. " + SHIFT + Z", { workspace = "r-1" }, "Previous relative workspace")
focus_with_workspace_flash(main_mod .. " + SHIFT + X", { workspace = "r+1" }, "Next relative workspace")
dispatch(main_mod .. " + minus", hl.dsp.workspace.toggle_special("magic"), "Toggle scratchpad")
dispatch(main_mod .. " + SHIFT + minus", hl.dsp.window.move({ workspace = "special:magic" }), "Move to scratchpad")
dispatch(main_mod .. " + equal", hl.dsp.workspace.toggle_special("dropdown"), "Toggle dropdown terminal")
dispatch(main_mod .. " + SHIFT + equal", hl.dsp.window.move({ workspace = "special:dropdown" }), "Move to dropdown workspace")

-- Zoom mode
bind(main_mod .. " + ALT + C", set_zoom_mode(2, "zoom"), "Enter zoom mode")
hl.define_submap("zoom", function()
  bind(main_mod .. " + ALT + C", set_zoom_mode(1, "reset"), "Exit zoom mode")
  bind("escape", set_zoom_mode(1, "reset"), "Exit zoom mode")
  bind("g", set_zoom_mode(1, "reset"), "Exit zoom mode")
  bind("catchall", set_zoom_mode(1, "reset"), "Exit zoom mode")
end)

-- Resize mode
dispatch(main_mod .. " + R", hl.dsp.submap("resize"), "Enter resize mode")
hl.define_submap("resize", function()
  for _, item in ipairs({
    { key = "LEFT", x = -20, y = 0, description = "Shrink left" },
    { key = "RIGHT", x = 20, y = 0, description = "Grow right" },
    { key = "UP", x = 0, y = -20, description = "Shrink up" },
    { key = "DOWN", x = 0, y = 20, description = "Grow down" },
    { key = "H", x = -20, y = 0, description = "Shrink left (Vim)" },
    { key = "L", x = 20, y = 0, description = "Grow right (Vim)" },
    { key = "K", x = 0, y = -20, description = "Shrink up (Vim)" },
    { key = "J", x = 0, y = 20, description = "Grow down (Vim)" },
  }) do
    dispatch(
      item.key,
      hl.dsp.window.resize({ x = item.x, y = item.y, relative = true }),
      item.description
    )
  end

  for _, item in ipairs({
    { key = "LEFT", x = -20, y = 0, description = "Move left" },
    { key = "RIGHT", x = 20, y = 0, description = "Move right" },
    { key = "UP", x = 0, y = -20, description = "Move up" },
    { key = "DOWN", x = 0, y = 20, description = "Move down" },
    { key = "H", x = -20, y = 0, description = "Move left (Vim)" },
    { key = "L", x = 20, y = 0, description = "Move right (Vim)" },
    { key = "K", x = 0, y = -20, description = "Move up (Vim)" },
    { key = "J", x = 0, y = 20, description = "Move down (Vim)" },
  }) do
    dispatch(
      "SHIFT + " .. item.key,
      hl.dsp.window.move({ x = item.x, y = item.y, relative = true }),
      item.description
    )
  end

  dispatch("c", hl.dsp.window.center(), "Center window")
  dispatch("escape", hl.dsp.submap("reset"), "Exit resize mode")
  dispatch("g", hl.dsp.submap("reset"), "Exit resize mode")
  dispatch("return", hl.dsp.submap("reset"), "Exit resize mode")
  dispatch("catchall", hl.dsp.submap("reset"), "Exit resize mode")
end)

-- Text and voice
exec(main_mod .. " + CTRL + O", "~/.local/bin/tts-selection", "Read selected text aloud")
exec(main_mod .. " + semicolon", "~/Projects/repos/llm-corrector-tui/bin/llm-corrector-field", "Correct focused field with local LLM", { release = true })
exec(main_mod .. " + C", "~/.local/bin/voice-input start", "Start voice input")
exec(main_mod .. " + C", "~/.local/bin/voice-input stop", "Stop voice input", { release = true })
dispatch(
  "F21",
  hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "M", window = "class:^([Vv]esktop|discord)$" }),
  "Toggle Discord mute"
)
dispatch(
  "F20",
  hl.dsp.send_shortcut({ mods = "CTRL SHIFT", key = "D", window = "class:^([Vv]esktop|discord)$" }),
  "Toggle Discord deafen"
)
exec("F13", "~/.config/session/idle-inhibit.sh toggle", "Toggle idle inhibitor")
exec("F14", "~/.local/bin/hypridle-suspend toggle", "Toggle suspend inhibitor")

-- Mouse
dispatch(main_mod .. " + mouse:272", hl.dsp.window.drag(), "Drag to move window", { mouse = true })
dispatch(main_mod .. " + mouse:273", hl.dsp.window.resize(), "Drag to resize window", { mouse = true })

-- Keep groupbars enabled by default, but make the decoration optional.
hl.bind(main_mod .. " + ALT + T", function()
  local enabled = hl.get_config("group.groupbar.enabled")
  if enabled == nil then
    enabled = true
  end

  hl.config({
    group = {
      groupbar = {
        enabled = not enabled,
      },
    },
  })
end, { description = "Toggle group title bar" })

return workspace_groups

-- Layer and window rules remain ordered data. Hyprland evaluates rule order,
-- so the list order here is intentional and should not be sorted.

local layer_rules = {
  {
    name = "slurp-noanim",
    match = { namespace = "selection" },
    no_anim = true,
  },
  {
    name = "quickshell-noanim",
    match = { namespace = "^quickshell.*" },
    no_anim = true,
    blur = true,
    ignore_alpha = 0.12,
  },
}

for _, rule in ipairs(layer_rules) do
  hl.layer_rule(rule)
end

local window_rules = {
  {
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
  },
  {
    name = "fix-xwayland-drags",
    match = {
      class = "^$",
      title = "^$",
      xwayland = true,
      float = true,
      fullscreen = false,
      pin = false,
    },
    no_focus = true,
  },
  {
    name = "chatgpt-pet-overlay",
    match = { class = "^[Cc]hat[Gg][Pp][Tt]$", float = true },
    no_blur = true,
    no_shadow = true,
    border_size = 0,
  },
  {
    name = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move = { 20, "monitor_h-120" },
    float = true,
  },
  {
    name = "dropdown-terminal",
    match = { class = "scratchpad" },
    float = true,
    workspace = "special:dropdown silent",
    size = { 800, 540 },
    center = true,
    stay_focused = true,
  },
  {
    name = "zen-pip",
    match = { class = "zen", title = "Picture-in-Picture" },
    float = true,
    size = { 480, 270 },
    move = { 1428, 774 },
    pin = true,
  },
  {
    name = "journal-float",
    match = { class = "journal" },
    float = true,
    size = { 1000, 700 },
    center = true,
  },
  {
    name = "pulsemixer-float",
    match = { class = "pulsemixer" },
    float = true,
    size = { 1000, 400 },
    center = true,
  },
  {
    name = "llm-corrector-float",
    match = { title = "^llm-corrector$" },
    float = true,
    size = { 720, 320 },
    center = true,
    stay_focused = true,
  },
  {
    name = "bitwarden-extension-float",
    match = { class = "^chrome-nngceckbapebfimnlniiiahkandclblb-Default$" },
    float = true,
    size = { 480, 620 },
    center = true,
  },
  {
    name = "zenity-color-float",
    match = { class = "zenity", title = "Copy color to Clipboard" },
    float = true,
  },
  {
    name = "dayz-render-unfocused",
    match = { class = "steam_app_221100" },
    render_unfocused = true,
  },
  {
    name = "dayz-launcher-float",
    match = { class = "steam_app_221100", title = "^DayZ Launcher$" },
    float = true,
    center = true,
  },
  {
    name = "dayz-drop-shadow",
    match = { title = "DropShadowWindow" },
    opacity = "0",
    no_focus = true,
    size = { 0, 0 },
  },
  {
    name = "rdr2-fullscreen",
    match = { class = "rdr2.exe" },
    fullscreen = true,
  },
  {
    name = "float-portal-file-dialog",
    match = { class = "xdg-desktop-portal-gtk" },
    float = true,
    size = { 800, 500 },
  },
  {
    name = "calcurse-float",
    match = { class = "calcurse" },
    float = true,
    size = { 1000, 700 },
    center = true,
  },
}

for _, rule in ipairs(window_rules) do
  hl.window_rule(rule)
end

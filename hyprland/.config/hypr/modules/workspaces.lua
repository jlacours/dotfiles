-- The physical workspace layout is the source of truth for rules and binds.

local workspace_groups = {
  {
    first = 1,
    last = 5,
    monitor = "HDMI-A-1",
    default = 1,
  },
  {
    first = 6,
    last = 10,
    monitor = "DP-1",
    default = 6,
  },
}

for _, group in ipairs(workspace_groups) do
  for workspace = group.first, group.last do
    hl.workspace_rule({
      workspace = tostring(workspace),
      monitor = group.monitor,
      default = workspace == group.default,
    })
  end
end

-- Normal workspaces lose gaps when only one tiled window is visible, or a
-- window is fullscreen. Special scratchpads keep their usual spacing.
for _, selector in ipairs({ "r[1-10]w[tv1]s[false]", "r[1-10]f[1]s[false]" }) do
  hl.workspace_rule({ workspace = selector, gaps_in = 0, gaps_out = 0 })
end

return workspace_groups

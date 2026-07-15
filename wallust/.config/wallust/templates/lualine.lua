local colors = {
  bg       = "{{background}}",
  bg_light = "{{background | lighten(0.1)}}",
  fg       = "{{foreground}}",
  color0   = "{{color0}}",
  color1   = "{{color1}}",
  color2   = "{{color2}}",
  color3   = "{{color3}}",
  color4   = "{{color4}}",
  color5   = "{{color5}}",
  color6   = "{{color6}}",
  color7   = "{{color7}}",
  color8   = "{{color8}}",
  color9   = "{{color9}}",
}

return {
  normal = {
    a = { fg = colors.bg, bg = colors.color4, gui = "bold" },
    b = { fg = colors.fg, bg = colors.bg_light },
    c = { fg = colors.fg, bg = colors.bg_light },
  },
  insert = {
    a = { fg = colors.bg, bg = colors.color2, gui = "bold" },
  },
  visual = {
    a = { fg = colors.bg, bg = colors.color5, gui = "bold" },
  },
  replace = {
    a = { fg = colors.bg, bg = colors.color1, gui = "bold" },
  },
  command = {
    a = { fg = colors.bg, bg = colors.color3, gui = "bold" },
  },
  inactive = {
    a = { fg = colors.color7, bg = colors.color8 },
    b = { fg = colors.color7, bg = colors.bg },
    c = { fg = colors.color7, bg = colors.bg },
  },
}

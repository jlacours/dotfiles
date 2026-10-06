{#- Mode-aware helpers: `light` is true when the background is bright.
    lift() moves away from the background's darkness (lighten on dark
    schemes, darken on light ones); sink() is its inverse. Dark schemes
    render exactly as plain lighten/darken did. -#}
{%- set light = ((background | red | int) * 299 + (background | green | int) * 587 + (background | blue | int) * 114) > 140000 -%}
{%- macro lift(c, a) -%}{% if light %}{{ c | darken(a) }}{% else %}{{ c | lighten(a) }}{% endif %}{%- endmacro -%}
{%- macro sink(c, a) -%}{% if light %}{{ c | lighten(a) }}{% else %}{{ c | darken(a) }}{% endif %}{%- endmacro -%}
local colors = {
  bg       = "{{background}}",
  bg_light = "{{ lift(background, 0.1) }}",
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

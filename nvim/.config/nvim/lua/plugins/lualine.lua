return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    -- Wallust-generated theme when present, darklime as fallback until wallust runs
    local theme = pcall(require, 'lualine.themes.wallust') and 'wallust' or 'darklime'
    require('lualine').setup({
      options = {
        globalstatus = true,
        theme = theme,
        section_separators = '',
        component_separators = '',
        always_show_tabline = false
      },
      sections = {
        lualine_x = { "codecompanion", "encoding", "fileformat", "filetype" },
      }
    })
    end
}

local M = {}

function M.reload()
  package.loaded["wallust"] = nil
  package.loaded["colors.wallust"] = nil
  package.loaded["lualine.themes.wallust"] = nil

  vim.cmd.colorscheme("wallust")

  local ok, lualine = pcall(require, "lualine")
  if ok then
    lualine.setup({
      options = {
        globalstatus = true,
        theme = "wallust",
        section_separators = "",
        component_separators = "",
        always_show_tabline = false,
      },
      sections = {
        lualine_x = { "codecompanion", "encoding", "fileformat", "filetype" },
      },
    })
  end
end

vim.api.nvim_create_user_command("WallustReload", M.reload, {
  desc = "Reload generated Wallust colorscheme and lualine theme",
})

vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "wallust",
  callback = function()
    package.loaded["lualine.themes.wallust"] = nil
  end,
})

return M

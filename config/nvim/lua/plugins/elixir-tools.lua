return {
 'elixir-tools/elixir-tools.nvim',
  version = "*",
  event = { "BufReadPre", "BufNewFile" },
  config = function ()
    local elixir = require('elixir')
    elixir.setup({
      nextls = {
        enable = true,
        init_options = {
          experimental = {
            completions = {
              enable = true
            }
          }
        }
      },
      credo = {
        enable = true
      },
      elixirls = {
        enable = true
      },
      on_attach = function(client, bufnr)
        vim.keymap.set("n", "<space>fp", ":ElixirFromPipe<cr>", { buffer = true, noremap = true })
        vim.keymap.set("n", "<space>tp", ":ElixirToPipe<cr>", { buffer = true, noremap = true })
        vim.keymap.set("v", "<space>em", ":ElixirExpandMacro<cr>", { buffer = true, noremap = true })
      end
    })
  end,
  dependencies = { 'nvim-lua/plenary.nvim' }
}

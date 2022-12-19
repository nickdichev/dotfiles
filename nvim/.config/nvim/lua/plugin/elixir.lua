local elixir = require('elixir')

elixir.setup({
  tag = 'v0.12.0',

  settings = elixir.settings({
    dialyzerEnabled = true,
    fetchDeps = false,
    enableTestLenses = false,
    suggestSpecs = false,
  }),

  
  capabilities = require('cmp_nvim_lsp').default_capabilities(),

  on_attach = function(client, bufnr)
    local map_opts = { buffer = true, noremap = true}

    -- run the codelens under the cursor
    vim.keymap.set("n", "<leader>r",  vim.lsp.codelens.run, map_opts)
    -- remove the pipe operator
    vim.keymap.set("n", "<leader>fp", ":ElixirFromPipe<cr>", map_opts)
    -- add the pipe operator
    vim.keymap.set("n", "<leader>tp", ":ElixirToPipe<cr>", map_opts)
    vim.keymap.set("v", "<leader>em", ":ElixirExpandMacro<cr>", map_opts)

    -- keybinds for vim-vsnip: https://github.com/hrsh7th/vim-vsnip
    vim.cmd([[imap <expr> <C-l> vsnip#available(1) ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>']])
    vim.cmd([[smap <expr> <C-l> vsnip#available(1) ? '<Plug>(vsnip-expand-or-jump)' : '<C-l>']])
  end
})

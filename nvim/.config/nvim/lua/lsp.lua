local opts = { noremap=true, silent=true }
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, opts)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, opts)

local lsp_formatting = function(bufnr)
    vim.lsp.buf.format({
        filter = function(client)
            -- apply whatever logic you want (in this example, we'll only use null-ls)
            return client.name == "null-ls"
        end,
        bufnr = bufnr,
    })
end

local augroup = vim.api.nvim_create_augroup("LspFormatting", {})


-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)
  print(vim.inspect(client.name))
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

  -- Mappings.
  -- See `:help vim.lsp.*` for documentation on any of the below functions
  local bufopts = { noremap=true, silent=true, buffer=bufnr }
  vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
  vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
  vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
  vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
  vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, bufopts)
  vim.keymap.set('n', '<leader>wa', vim.lsp.buf.add_workspace_folder, bufopts)
  vim.keymap.set('n', '<leader>wr', vim.lsp.buf.remove_workspace_folder, bufopts)
  vim.keymap.set('n', '<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workleader_folders()))
  end, bufopts)
  vim.keymap.set('n', '<leader>D', vim.lsp.buf.type_definition, bufopts)
  vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, bufopts)
  vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
  vim.keymap.set('n', '<leader>mf', function() lsp_formatting(bufnr) end, bufopts)

  if client.supports_method("textDocument/formatting") then
    vim.api.nvim_clear_autocmds({ group = augroup, buffer = bufnr })
    vim.api.nvim_create_autocmd("BufWritePre", {
        group = augroup,
        buffer = bufnr,
        callback = function()
            lsp_formatting(bufnr)
        end,
    })
  end
end

local on_attach_elixir = function(client, bufnr)
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

  return on_attach(client, bufnr)
end

local lsp_flags = {
  -- This is the default in Nvim 0.7+
  debounce_text_changes = 150,
}

local capabilities = require('cmp_nvim_lsp').default_capabilities()

require('lspconfig')['elixirls'].setup{
  cmd = { os.getenv('HOME') .. '/.ls/elixir-ls/language_server.sh' },
  on_attach = on_attach_elixir,
  capabilities = capabilities,
  settings = {
    dialyzerEnabled = true,
    fetchDeps = false,
    enableTestLenses = true,
    suggestSpecs = false,
  }
}

require('lspconfig')['clojure_lsp'].setup{
  cmd = { os.getenv('HOME') .. '/.ls/clojure-lsp/clojure-lsp' },
  on_attach = on_attach,
  capabilities = capabilities,
  settings = { }
}

require('lspconfig')['kotlin_language_server'].setup{
  cmd = { os.getenv('HOME') .. '/.ls/kotlin-language-server/server/bin/kotlin-language-server' },
  on_attach = on_attach,
  capabilities = capabilities,
  settings = { }
}

local null_ls = require("null-ls")
null_ls.setup({
    sources = {
        null_ls.builtins.formatting.fnlfmt,
        null_ls.builtins.formatting.mix,
        null_ls.builtins.diagnostics.ktlint
    },
    on_attach = on_attach,
})


require('nvim-treesitter.configs').setup({
  ensure_installed = {
    "clojure",
    "elixir",
    "erlang",
    "fennel",
    "hcl",
    "heex",
    "html",
    "javascript",
    "json",
    "kotlin",
    "lua",
    "markdown",
    "toml",
    "yaml"
  },
  highlight = { enable = true },
  indent = { enable = true },
  matchup = { enable = true },
  rainbow = { enable = true },
  textobjects = {
    select = {
      enable = true,
      lookahead = true,

      keymaps = {
        ["ab"] = "@block.outer",
        ["ib"] = "@block.inner",
        ["af"] = "@function.outer",
        ["if"] = "@function.inner",
        ["ac"] = "@class.outer",
        ["ic"] = "@class.inner"
      },

      selection_modes = {
        ['@parameter.outer'] = 'v', -- charwise
        ['@function.outer'] = 'V', -- linewise
        ['@class.outer'] = '<c-v>', -- blockwise
      },

      include_surrounding_whitespace = true,
    },
  },
})

local elixir = require('elixir')
local lsp_helpers = require('lsp_helpers')

elixir.setup({
  cmd = lsp_helpers.elixirls_cmd(),
  settings = elixir.settings({
    enableTestLenses = true,
  }),
})

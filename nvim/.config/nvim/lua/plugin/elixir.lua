local elixir = require('elixir')
local elixirls = require('elixir.elixirls')
local lsp_helpers = require('lsp_helpers')

elixir.setup({
  credo = {enable = true},
  elixirls = {
    cmd = lsp_helpers.elixirls_cmd(),
    settings = elixirls.settings({
      enableTestLenses = true
    })
  }
})

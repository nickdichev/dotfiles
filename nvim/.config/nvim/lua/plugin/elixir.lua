local elixir = require('elixir')

elixir.setup({
  cmd = os.getenv('HOME') .. '/.ls/elixir-ls/language_server.sh',
  settings = elixir.settings({
    enableTestLenses = true,
  }),
})

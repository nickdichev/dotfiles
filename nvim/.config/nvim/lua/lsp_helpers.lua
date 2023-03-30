local is_devenv = function()
  return os.getenv('DEVENV_ROOT')
end

local elixirls_cmd = function()
  if is_devenv() then
    return os.getenv('DEVENV_PROFILE') .. '/bin/elixir-ls'
  else
    return os.getenv('HOME') .. '/.ls/elixir-ls/language_server.sh'
  end
end

return { elixirls_cmd = elixirls_cmd }

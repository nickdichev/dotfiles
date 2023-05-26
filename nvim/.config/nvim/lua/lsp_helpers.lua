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

local kotlinls_cmd = function()
  if is_devenv() then
    return os.getenv('DEVENV_PROFILE') .. '/bin/kotlin-language-server'
  else
    return os.getenv('HOME') .. '/.ls/kotlin-language-server/server/build/install/server/bin/kotlin-language-server'
  end
end

local pyright_cmd = function()
  if is_devenv() then
    return os.getenv('DEVENV_PROFILE') .. '/bin/pyright-langserver'
  else
    return os.getenv('HOME') .. './ls/pyright/pyright-langserver'
  end
end

return { elixirls_cmd = elixirls_cmd, kotlinls_cmd = kotlinls_cmd, pyright_cmd = pyright_cmd }

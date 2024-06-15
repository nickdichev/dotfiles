local is_devenv = function()
	return os.getenv("DEVENV_ROOT")
end

local elixirls_cmd = function()
	if is_devenv() then
		return os.getenv("DEVENV_PROFILE") .. "/bin/elixir-ls"
	end
end

local nextls_cmd = function()
	return os.getenv("HOME") .. "/.nix-profile/bin/nextls"
end

return { elixirls_cmd = elixirls_cmd, nextls_cmd = nextls_cmd }

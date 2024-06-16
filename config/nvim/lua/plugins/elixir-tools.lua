local map = require("core.utils").map

return {
	"elixir-tools/elixir-tools.nvim",
	version = "*",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local elixir = require("elixir")
		local elixirls = require("elixir.elixirls")
		local lsp_helpers = require("lsp_helpers")

		elixir.setup({
			nextls = {
				enable = false,
				cmd = lsp_helpers.nextls_cmd(),
				init_options = {
					experimental = {
						completions = {
							enable = true,
						},
					},
				},
			},
			credo = {
				enable = true,
			},
			elixirls = {
				enable = false,
				cmd = lsp_helpers.elixirls_cmd(),
				settings = elixirls.settings({
					dialyzerEnabled = false,
					enableTestLenses = true,
				}),
				on_attach = function(client, bufnr)
					map("n", "<leader>fp", ":ElixirFromPipe<CR>", { buffer = true })
					map("n", "<leader>tp", ":ElixirToPipe<CR>", { buffer = true })
					map("v", "<leader>em", ":ElixirExpandMacro<CR>", { buffer = true })
				end,
			},
		})
	end,
	dependencies = { "nvim-lua/plenary.nvim" },
}

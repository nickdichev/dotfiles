local map = require("core.utils").map

local capabilities = vim.lsp.protocol.make_client_capabilities()
local has_cmp_nvim_lsp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
if has_cmp_nvim_lsp then
	capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
end

vim.lsp.config("*", {
	capabilities = capabilities,
})

local function buf_map(opts, mode, lhs, rhs, desc)
	map(mode, lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
end

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
	callback = function(event)
		local opts = { buffer = event.buf }

		buf_map(opts, "n", "gd", vim.lsp.buf.definition, "Go to definition")
		buf_map(opts, "n", "K", vim.lsp.buf.hover, "Hover")
		buf_map(opts, "n", "<leader>vws", vim.lsp.buf.workspace_symbol, "Workspace symbols")
		buf_map(opts, "n", "<leader>vd", vim.diagnostic.open_float, "Line diagnostics")
		buf_map(opts, "n", "[d", function()
			vim.diagnostic.jump({ count = -1, float = true })
		end, "Previous diagnostic")
		buf_map(opts, "n", "]d", function()
			vim.diagnostic.jump({ count = 1, float = true })
		end, "Next diagnostic")
		buf_map(opts, "n", "<leader>vca", vim.lsp.buf.code_action, "Code action")
		buf_map(opts, "n", "<leader>vrr", vim.lsp.buf.references, "References")
		buf_map(opts, "n", "<leader>vrn", vim.lsp.buf.rename, "Rename")
		buf_map(opts, "i", "<C-h>", vim.lsp.buf.signature_help, "Signature help")
	end,
})

-- show diagnostics as "virtual lines" in the buffer
vim.diagnostic.config({
	virtual_lines = {
		-- Only show virtual line diagnostics for the current cursor line
		current_line = true,
	},
})

vim.lsp.enable({
	"basedpyright",
	"clojure-lsp",
	"expert",
	"gopls",
	"lua-language-server",
	"nil-ls",
	"postgres-language-server",
	"tofu-ls",
	"ts_ls",
})

return {
	{
		"Sebastian-Nielsen/better-type-hover",
		ft = { "typescript", "typescriptreact" },
		config = function()
			require("better-type-hover").setup()
		end,
	},
}

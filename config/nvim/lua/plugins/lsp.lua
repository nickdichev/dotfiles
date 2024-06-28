local map = require("core.utils").map

local lsp_init_function = function()
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
		callback = function(event)
			local opts = { buffer = event.buf }

			map("n", "gd", function()
				vim.lsp.buf.definition()
			end, opts)
			map("n", "K", function()
				vim.lsp.buf.hover()
			end, opts)
			map("n", "<leader>vws", function()
				vim.lsp.buf.workspace_symbol()
			end, opts)
			map("n", "<leader>vd", function()
				vim.diagnostic.open_float()
			end, opts)
			map("n", "[d", function()
				vim.diagnostic.goto_next()
			end, opts)
			map("n", "]d", function()
				vim.diagnostic.goto_prev()
			end, opts)
			map("n", "<leader>vca", function()
				vim.lsp.buf.code_action()
			end, opts)
			map("n", "<leader>vrr", function()
				vim.lsp.buf.references()
			end, opts)
			map("n", "<leader>vrn", function()
				vim.lsp.buf.rename()
			end, opts)
			map("i", "<C-h>", function()
				vim.lsp.buf.signature_help()
			end, opts)
		end,
	})
end

local lsp_config_function = function()
	local lsp_zero = require("lsp-zero")

	-- mason
	require("mason").setup({ ui = { border = "rounded" } })

	require("mason-lspconfig").setup({
		automatic_installation = false,
		handlers = { lsp_zero.default_setup },
	})

	-- lsp config
	local lspconfig = require("lspconfig")
	lspconfig.nil_ls.setup({})

	lspconfig.lua_ls.setup({
		settings = {
			Lua = {
				format = { enable = false },
				hint = { enable = true },
			},
		},
	})

	lspconfig.lexical.setup({
		filetypes = { "elixir", "eelixir", "heex" },
		cmd = { "lexical" },
		root_dir = function(fname)
			return lspconfig.util.root_pattern("mix.exs", ".git")(fname) or nil
		end,
	})

	lspconfig.pyright.setup({})

	vim.api.nvim_create_autocmd("InsertEnter", {
		callback = function()
			vim.lsp.inlay_hint.enable(false)
		end,
	})
	vim.api.nvim_create_autocmd("InsertLeave", {
		callback = function()
			vim.lsp.inlay_hint.enable(vim.b.inlay_hints_enabled or false)
		end,
	})

	local handlers = vim.lsp.handlers
	handlers["textDocument/hover"] = vim.lsp.with(handlers.hover, { border = "rounded" })
	handlers["textDocument/signatureHelp"] = vim.lsp.with(handlers.signature_help, { border = "rounded" })
end

return {
	{
		"VonHeikemen/lsp-zero.nvim",
		event = "BufRead",
		dependencies = {
			"neovim/nvim-lspconfig",
			"williamboman/mason-lspconfig.nvim",
			"williamboman/mason.nvim",
		},
		init = lsp_init_function,
		config = lsp_config_function,
	},
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {},
	},
}

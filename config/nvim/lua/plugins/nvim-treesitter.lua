local parsers = {
	"astro",
	"css",
	"eex",
	"elixir",
	"erlang",
	"go",
	"hcl",
	"heex",
	"html",
	"javascript",
	"json",
	"kdl",
	"lua",
	"markdown",
	"markdown_inline",
	"nix",
	"python",
	"surface",
	"toml",
	"tsx",
	"typescript",
	"yaml",
}

local highlight_filetypes = {
	"astro",
	"css",
	"eelixir",
	"elixir",
	"erlang",
	"go",
	"hcl",
	"heex",
	"html",
	"javascript",
	"javascript.jsx",
	"javascriptreact",
	"jsx",
	"json",
	"jsonc",
	"kdl",
	"lua",
	"markdown",
	"nix",
	"python",
	"sface",
	"surface",
	"toml",
	"typescript",
	"typescript.tsx",
	"typescriptreact",
	"yaml",
}

local language_aliases = {
	{ lang = "eex", filetypes = { "eelixir" } },
	{ lang = "javascript", filetypes = { "javascript.jsx", "javascriptreact", "jsx" } },
	{ lang = "json", filetypes = { "jsonc" } },
	{ lang = "surface", filetypes = { "sface" } },
	{ lang = "tsx", filetypes = { "typescript.tsx", "typescriptreact" } },
}

local install_dir = vim.fn.stdpath("data") .. "/site"
local install_opts = { max_jobs = 4 }

local function start_treesitter()
	pcall(vim.treesitter.start)
end

local function register_language_aliases()
	for _, alias in ipairs(language_aliases) do
		vim.treesitter.language.register(alias.lang, alias.filetypes)
	end
end

local function add_plugin_runtime(treesitter)
	local source = debug.getinfo(treesitter.setup, "S").source
	local init_lua = source:sub(1, 1) == "@" and source:sub(2) or source
	local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(init_lua)))
	local runtime_dir = vim.fs.joinpath(plugin_root, "runtime")

	if vim.uv.fs_stat(runtime_dir) then
		vim.opt.runtimepath:prepend(runtime_dir)
	end
end

local function setup_treesitter()
	local ok, treesitter = pcall(require, "nvim-treesitter")
	if ok and type(treesitter.setup) == "function" then
		add_plugin_runtime(treesitter)
		treesitter.setup({
			install_dir = install_dir,
		})
		return treesitter
	end

	local legacy_ok, legacy_configs = pcall(require, "nvim-treesitter.configs")
	if legacy_ok then
		legacy_configs.setup({
			ensure_installed = parsers,
			highlight = {
				enable = true,
			},
		})
	end

	return nil
end

local function build_treesitter()
	local treesitter = setup_treesitter()
	if type(treesitter) == "table" and type(treesitter.install) == "function" then
		treesitter.install(parsers, install_opts):wait(300000)
		if type(treesitter.update) == "function" then
			treesitter.update(parsers, install_opts):wait(300000)
		end
		return
	end

	if vim.fn.exists(":TSUpdate") == 2 then
		vim.cmd.TSUpdate()
		return
	end

	vim.notify("nvim-treesitter main API is unavailable; run :Lazy update nvim-treesitter", vim.log.levels.WARN)
end

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = build_treesitter,
		config = function()
			setup_treesitter()
			register_language_aliases()

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("user_treesitter_highlight", { clear = true }),
				pattern = highlight_filetypes,
				callback = start_treesitter,
			})

			if vim.tbl_contains(highlight_filetypes, vim.bo.filetype) then
				start_treesitter()
			end
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		event = "BufRead",
		config = function()
			require("nvim-treesitter-textobjects").setup({
				select = {
					lookahead = true,
					selection_modes = {
						["@parameter.outer"] = "v",
						["@function.outer"] = "V",
						["@class.outer"] = "<c-v>",
					},
					include_surrounding_whitespace = true,
				},
			})

			local ts_select = require("nvim-treesitter-textobjects.select")
			vim.keymap.set({ "x", "o" }, "ab", function()
				ts_select.select_textobject("@block.outer", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "ib", function()
				ts_select.select_textobject("@block.inner", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "af", function()
				ts_select.select_textobject("@function.outer", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "if", function()
				ts_select.select_textobject("@function.inner", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "ac", function()
				ts_select.select_textobject("@class.outer", "textobjects")
			end)
			vim.keymap.set({ "x", "o" }, "ic", function()
				ts_select.select_textobject("@class.inner", "textobjects")
			end)
		end,
	},
	{
		"nvim-treesitter/nvim-treesitter-context",
		event = "BufRead",
		opts = {
			enable = true,
		},
	},
}

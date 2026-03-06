return {
	{
		"nvim-treesitter/nvim-treesitter",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter.install").compilers = { vim.g.gcc_bin_path }
			require("nvim-treesitter").setup({
				ensure_installed = {
					"elixir",
					"erlang",
					"go",
					"hcl",
					"heex",
					"html",
					"javascript",
					"json",
					"lua",
					"markdown",
					"nix",
					"python",
					"typescript",
					"kdl",
					"toml",
					"yaml",
					"css",
					"astro",
				},
			})
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

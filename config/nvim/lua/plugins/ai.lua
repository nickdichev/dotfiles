return {
	-- {
	-- 	"zbirenbaum/copilot.lua",
	-- 	enabled = true,
	-- 	event = "VeryLazy",
	-- 	opts = {
	-- 		suggestion = {
	-- 			enabled = true,
	-- 			auto_trigger = true,
	-- 			debounce = 75,
	-- 		},
	-- 		filetypes = {
	-- 			yaml = true,
	-- 			gitcommit = true,
	-- 			markdown = true,
	-- 		},
	-- 		copilot_node_command = vim.g.nodejs_bin_path,
	-- 	},
	-- },
	-- {
	-- 	"CopilotC-Nvim/CopilotChat.nvim",
	-- 	branch = "canary",
	-- 	dependencies = {
	-- 		{ "zbirenbaum/copilot.lua" },
	-- 		{ "nvim-lua/plenary.nvim" },
	-- 	},
	-- 	opts = {},
	-- 	init = function()
	-- 		local function pick_with_selection(selection)
	-- 			return function()
	-- 				local actions = require("CopilotChat.actions")
	-- 				actions.pick(actions.prompt_actions({ selection = require("CopilotChat.select")[selection] }))
	-- 			end
	-- 		end
	-- 		map({ "n", "v", "x" }, "<leader>cc", function()
	-- 			require("CopilotChat").toggle()
	-- 		end)
	-- 		map({ "n", "v", "x" }, "<leader>cb", pick_with_selection("buffer"))
	-- 		map({ "n", "v", "x" }, "<leader>ca", pick_with_selection("buffers"))
	-- 		map({ "n", "v", "x" }, "<leader>cs", pick_with_selection("visual"))
	-- 	end,
	-- },
	{
		"yetone/avante.nvim",
		event = "VeryLazy",
		lazy = false,
		version = false, -- set this if you want to always pull the latest change
		opts = {
			file_selector = {
				provider = "telescope",
				provider_opts = {
					get_filepaths = function(params)
						local cwd = params.cwd ---@type string
						local selected_filepaths = params.selected_filepaths ---@type string[]
						local cmd = string.format("rg --files --hidden -g !.git -g !.devenv")
						local output = vim.fn.system(cmd)
						local filepaths = vim.split(output, "\n", { trimempty = true })
						return vim.iter(filepaths)
							:filter(function(filepath)
								return not vim.tbl_contains(selected_filepaths, filepath)
							end)
							:totable()
					end,
				},
			},
		},
		-- if you want to build from source then do `make BUILD_FROM_SOURCE=true`
		build = "make",
		-- build = "powershell -ExecutionPolicy Bypass -File Build.ps1 -BuildFromSource false" -- for windows
		dependencies = {
			"stevearc/dressing.nvim",
			"nvim-lua/plenary.nvim",
			"MunifTanjim/nui.nvim",
			{
				-- support for image pasting
				"HakonHarnes/img-clip.nvim",
				event = "VeryLazy",
				opts = {
					-- recommended settings
					default = {
						embed_image_as_base64 = false,
						prompt_for_file_name = false,
						drag_and_drop = {
							insert_mode = true,
						},
						-- required for Windows users
						use_absolute_path = true,
					},
				},
			},
			{
				-- Make sure to set this up properly if you have lazy=true
				"MeanderingProgrammer/render-markdown.nvim",
				opts = {
					file_types = { "markdown", "Avante" },
				},
				ft = { "markdown", "Avante" },
			},
		},
	},
}

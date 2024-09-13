local map = require("core.utils").map

return {
	{
		"zbirenbaum/copilot.lua",
		enabled = true,
		event = "VeryLazy",
		opts = {
			suggestion = {
				enabled = true,
				auto_trigger = true,
				debounce = 75,
			},
			filetypes = {
				yaml = true,
				gitcommit = true,
				markdown = true,
			},
			copilot_node_command = vim.g.nodejs_bin_path,
		},
	},
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		branch = "canary",
		dependencies = {
			{ "zbirenbaum/copilot.lua" },
			{ "nvim-lua/plenary.nvim" },
		},
		opts = {},
		init = function()
			local function pick_with_selection(selection)
				return function()
					local actions = require("CopilotChat.actions")
					actions.pick(actions.prompt_actions({ selection = require("CopilotChat.select")[selection] }))
				end
			end
			map({ "n", "v", "x" }, "<leader>cc", function()
				require("CopilotChat").toggle()
			end)
			map({ "n", "v", "x" }, "<leader>cb", pick_with_selection("buffer"))
			map({ "n", "v", "x" }, "<leader>ca", pick_with_selection("buffers"))
			map({ "n", "v", "x" }, "<leader>cs", pick_with_selection("visual"))
		end,
	},
	{
		"joshuavial/aider.nvim",
		opts = {},
		init = function()
			local aider = require("aider")
			map({ "n", "v", "x" }, "<leader>aa", function()
				aider.AiderOpen()
			end)
		end,
	},
}

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
				keymap = {
					accept = "<M-m>",
				},
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
		"yetone/avante.nvim",
		enabled = false,
		event = "VeryLazy",
		lazy = false,
		version = false,
		opts = {
			provider = "claude",
			auto_suggestion_provider = "copilot",
			cursor_applying_provider = "groq",
			behaviour = {
				enable_cursor_planning_mode = true,
				auto_suggestions = false,
			},
			claude = {
				api_key_name = "cmd:rbw get ANTHROPIC_API_KEY_PERSONAL",
			},
			groq = {
				api_key_name = "cmd:rbw get GROQ_API_KEY",
			},
			vendors = {
				groq = {
					__inherited_from = "openai",
					api_key_name = "GROQ_API_KEY",
					endpoint = "https://api.groq.com/openai/v1/",
					model = "llama-3.3-70b-versatile",
					max_tokens = 32768,
				},
				codegemma = {
					__inherited_from = "openai",
					api_key_name = "",
					endpoint = "http://127.0.0.1:11434/v1",
					model = "codegemma:2b",
				},
			},
			web_search_engine = {
				provider = "kagi",
			},
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
	{
		"olimorris/codecompanion.nvim",
		opts = {
			adapters = {
				anthropic = function()
					return require("codecompanion.adapters").extend("anthropic", {
						env = {
							api_key = "rbw get ANTHROPIC_API_KEY_PERSONAL",
						},
					})
				end,
			},
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
		},
	},
	{
		"ravitemer/mcphub.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim", -- Required for Job and HTTP requests
		},
		branch = "main",
		build = "bundled_build.lua",
		config = function()
			require("mcphub").setup({
				-- Required options
				port = 3333, -- Port for MCP Hub server
				config = vim.fn.expand("~/.config/mcphub/mcpservers.json"), -- Absolute path to config file
				use_bundled_binary = true,
			})
			-- require("avante").setup({
			-- 	-- Dynamic system prompt with active servers
			-- 	system_prompt = function()
			-- 		local hub = require("mcphub").get_hub_instance()
			-- 		return hub:get_active_servers_prompt()
			-- 	end,
			-- 	-- Load MCP tool dynamically
			-- 	custom_tools = function()
			-- 		return {
			-- 			require("mcphub.extensions.avante").mcp_tool(),
			-- 		}
			-- 	end,
			-- })
			require("codecompanion").setup({
				strategies = {
					chat = {
						tools = {
							["mcp"] = {
								-- calling it in a function would prevent mcphub from being loaded before it's needed
								callback = function()
									return require("mcphub.extensions.codecompanion")
								end,
								description = "Call tools and resources from the MCP Servers",
							},
						},
					},
				},
			})
		end,
	},
}

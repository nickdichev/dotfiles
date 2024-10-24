local bo = vim.bo
local fn = vim.fn

--------------------------------------------------------------------------------

--- https://github.com/nvim-lualine/lualine.nvim/blob/master/lua/lualine/components/branch/git_branch.lua#L118
---@nodiscard
---@return boolean
local function isStandardBranch()
	local curBranch = require("lualine.components.branch.git_branch").get_branch()
	local notMainBranch = curBranch ~= "main" and curBranch ~= "master"
	local validFiletype = bo.filetype ~= "help" -- vim help files are located in a git repo
	local notSpecialBuffer = bo.buftype == ""
	return notMainBranch and validFiletype and notSpecialBuffer
end

--------------------------------------------------------------------------------

local function selectionCount()
	local isVisualMode = fn.mode():find("[Vv]")
	if not isVisualMode then
		return ""
	end
	local starts = fn.line("v")
	local ends = fn.line(".")
	local lines = starts <= ends and ends - starts + 1 or starts - ends + 1
	return " " .. tostring(lines) .. "L " .. tostring(fn.wordcount().visual_chars) .. "C"
end

-- shows global mark M
vim.api.nvim_del_mark("M") -- reset on session start
local function markM()
	local markObj = vim.api.nvim_get_mark("M", {})
	local markLn = markObj[1]
	local markBufname = vim.fs.basename(markObj[4])
	if markBufname == "" then
		return ""
	end -- mark not set
	return " " .. markBufname .. ":" .. markLn
end

local function treesitter_context()
	return require("nvim-treesitter").statusline(90)
end

--------------------------------------------------------------------------------

---improves upon the default statusline components by having properly working icons
---@nodiscard
local function currentFile()
	local maxLen = 25

	local ext = fn.expand("%:e")
	local ft = bo.filetype
	local name = fn.expand("%:t")
	if ft == "octo" and name:find("^%d$") then
		name = "#" .. name
	elseif ft == "TelescopePrompt" then
		name = "Telescope"
	end

	local deviconsInstalled, devicons = pcall(require, "nvim-web-devicons")
	local ftOrExt = ext ~= "" and ext or ft
	if ftOrExt == "javascript" then
		ftOrExt = "js"
	end
	if ftOrExt == "typescript" then
		ftOrExt = "ts"
	end
	if ftOrExt == "markdown" then
		ftOrExt = "md"
	end
	if ftOrExt == "vimrc" then
		ftOrExt = "vim"
	end
	local icon = deviconsInstalled and devicons.get_icon(name, ftOrExt) or ""
	-- add sourcegraph icon for clarity
	if fn.expand("%"):find("^sg") then
		icon = "󰓁 " .. icon
	end

	-- truncate
	local nameNoExt = name:gsub("%.%w+$", "")
	if #nameNoExt > maxLen then
		name = nameNoExt:sub(1, maxLen) .. "…" .. ext
	end

	if icon == "" then
		return name
	end
	return icon .. " " .. name
end

--------------------------------------------------------------------------------

-- FIX Add missing buffer names for current file component
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "lazy", "mason", "TelescopePrompt", "noice" },
	callback = function()
		local name = vim.fn.expand("<amatch>")
		name = name:sub(1, 1):upper() .. name:sub(2) -- capitalize
		pcall(vim.api.nvim_buf_set_name, 0, name)
	end,
})

-- nerdfont: powerline icons have the prefix 'ple-'
local bottomSeparators = { left = "", right = "" }
local topSeparators = { left = "", right = "" }
local emptySeparators = { left = "", right = "" }

local lualineConfig = {
	-- INFO using the tabline will override vim's default tabline, so the tabline
	-- should always include the tab element
	tabline = {
		lualine_a = {},
		lualine_b = {
			{ treesitter_context, section_separators = topSeparators },
		},
		lualine_c = {},
		lualine_x = {},
		-- INFO dap and recording status defined in the respective plugin configs
		-- for lualine_y and lualine_z for their lazy loading
		lualine_y = {
			{ markM },
		},
		lualine_z = {},
	},
	sections = {
		lualine_a = {
			{ "branch", cond = isStandardBranch },
			{ currentFile },
			{ "lsp_progress" },
		},
		lualine_b = {
			-- { require("funcs.alt-alt").altFileStatusline },
		},
		lualine_c = {
			-- { require("funcs.quickfix").counter },
		},
		lualine_x = {
			"diagnostics",
			{ "copilot", symbols = { show_colors = true } },
		},
		lualine_y = {
			"diff",
		},
		lualine_z = {
			{ selectionCount, padding = { left = 0, right = 1 } },
			"location",
		},
	},
	options = {
		refresh = { statusline = 1000 },
		ignore_focus = {
			"DressingInput",
			"DressingSelect",
			"ccc-ui",
		},
		globalstatus = true,
		component_separators = { left = "", right = "" },
		section_separators = bottomSeparators,
	},
}

--------------------------------------------------------------------------------

return {
	"nvim-lualine/lualine.nvim",
	lazy = false, -- load immediately so there is no flickering
	dependencies = { "nvim-tree/nvim-web-devicons", "arkav/lualine-lsp-progress", "AndreM222/copilot-lualine" },
	opts = lualineConfig,
}

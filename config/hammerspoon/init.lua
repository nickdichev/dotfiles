-- Ensure spoons directory is in package.path (needed for custom configdir)
package.path = hs.configdir .. "/spoons/?.spoon/init.lua;" .. package.path

-- Auto-reload on config changes
local _configWatcher = hs.pathwatcher
	.new(hs.configdir, function(files)
		for _, file in ipairs(files) do
			if file:sub(-4) == ".lua" then
				hs.reload()
				return
			end
		end
	end)
	:start()

-- Features (uncomment as needed)
-- require("features.hyperkey")      -- Hyper key app launcher with visual overlay (needs HyperKey.spoon)
-- require("features.audio-switcher") -- Cmd+Shift+Space audio device chooser
require("features.text-expander") -- Snippet expansion (;date, ;time, etc.)
-- require("features.domain-swapper") -- Safari URL domain swapping
require("features.vim-mode") -- Vim motions everywhere (needs VimMode.spoon)
-- require("features.mute-on-sleep")  -- Mute speakers on wake from sleep

hs.alert.show("Hammerspoon loaded")

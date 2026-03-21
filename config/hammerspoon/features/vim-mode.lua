-- VimMode.spoon: Vim motions in every macOS text field.
-- Vendored via nix in modules/hammerspoon.nix

local VimMode = hs.loadSpoon("VimMode")
local vim = VimMode:new()

-- Disable in apps that have their own vim mode
vim:disableForApp("Ghostty")
vim:disableForApp("Terminal")
vim:disableForApp("Neovim")
vim:disableForApp("Code")

-- Enter normal mode by typing jk quickly
vim:enterWithSequence("jk")

-- Menubar indicator showing current mode + disable toggle
local menubar = hs.menubar.new()
local isEnabled = true

local function updateMenubar(mode)
  if not isEnabled then
    menubar:setTitle("VIM: OFF")
    return
  end
  menubar:setTitle(mode or "VIM")
end

-- Watch for mode changes via a timer that checks the spoon state
local modeWatcher = hs.timer.new(0.5, function()
  if not isEnabled then return end
  -- VimMode.spoon shows alerts for mode changes; we mirror in menubar
  updateMenubar("VIM")
end)
modeWatcher:start()

menubar:setMenu({
  {
    title = "Toggle VimMode (for sharing screen)",
    fn = function()
      isEnabled = not isEnabled
      if isEnabled then
        vim:enable()
        updateMenubar("VIM")
        hs.alert.show("VimMode enabled")
      else
        vim:disable()
        updateMenubar("VIM: OFF")
        hs.alert.show("VimMode disabled")
      end
    end,
  },
})

updateMenubar("VIM")

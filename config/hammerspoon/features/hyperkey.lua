local HyperKey = hs.loadSpoon("HyperKey")

-- Hyper = Cmd+Alt+Ctrl+Shift (bind this to a single key on your Glove80)
hyperKey = HyperKey:new({ "cmd", "alt", "ctrl", "shift" })

hyperKey
  :bind("s"):toApplication("/Applications/Safari.app")
  :bind("g"):toApplication("/Applications/Ghostty.app")
  :bind("o"):toApplication("/Applications/Obsidian.app")
  :bind("k"):toApplication("/Applications/Slack.app")
  :bind("d"):toApplication("/Applications/Discord.app")
  :bind("r"):toFunction("Reload Hammerspoon", hs.reload)
  :bind("l"):toFunction("Lock Screen", hs.caffeinate.startScreensaver)

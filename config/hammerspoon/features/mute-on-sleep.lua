-- Mute audio on wake from sleep to prevent embarrassing blasts.
-- Skips allowlisted devices (headphones, DACs, etc.).
--
-- To find your device names, run in the Hammerspoon console:
--   hs.fnutils.each(hs.audiodevice.allOutputDevices(), function(d) print(d:name()) end)

local allowedPatterns = {
  -- Add your headphone/DAC patterns here, e.g.:
  -- "AirPods",
  -- "WH-1000",
}

local function isAllowlisted(device)
  for _, pattern in ipairs(allowedPatterns) do
    if device:name():match(pattern) then
      return true
    end
  end
  return false
end

local sleepWatcher = hs.caffeinate.watcher.new(function(state)
  if state ~= hs.caffeinate.watcher.systemDidWake then
    return
  end

  local device = hs.audiodevice.defaultOutputDevice()
  if not device then
    return
  end

  if isAllowlisted(device) then
    return
  end

  device:setMuted(true)
  hs.alert.show("Muted " .. device:name())
end)

sleepWatcher:start()

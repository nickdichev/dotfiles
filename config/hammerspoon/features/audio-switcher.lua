-- Quick audio output device switcher via a chooser popup.

local function getDeviceChoices()
  local devices = hs.audiodevice.allOutputDevices()
  local choices = {}

  for i, device in ipairs(devices) do
    local icon = device:outputMuted() and "🔇" or "🔊"
    local subText = icon
    if device:outputVolume() then
      subText = subText .. " Volume " .. math.floor(device:outputVolume()) .. "%"
    end

    choices[i] = {
      text = device:name(),
      subText = subText,
      uuid = device:uid(),
    }
  end

  return choices
end

local function handleChoice(choice)
  if not choice then return end

  local device = hs.audiodevice.findDeviceByUID(choice.uuid)
  device:setDefaultOutputDevice()
  device:setOutputMuted(false)
  hs.alert.show("Switched to " .. choice.text)
end

local chooser = hs.chooser.new(handleChoice)
chooser:width(25)

hs.hotkey.bind({ "cmd", "shift" }, "space", function()
  chooser:choices(getDeviceChoices())
  chooser:show()
end)

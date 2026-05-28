-- Swap the domain of the current Safari tab URL.
-- Useful for switching between localhost/staging/production.

local function getSafariUrl()
  local app = hs.application.frontmostApplication()
  if not app or app:bundleID() ~= "com.apple.Safari" then
    return nil
  end

  local ok, url = hs.osascript.applescript(
    'tell application "Safari" to get URL of current tab of front window'
  )
  if ok then
    return url
  end
  return nil
end

local function setSafariUrl(newUrl)
  hs.osascript.applescript(
    'tell application "Safari" to set URL of current tab of front window to "' .. newUrl .. '"'
  )
end

local function swapToDomain(domain, protocol)
  protocol = protocol or "https"
  return function()
    local url = getSafariUrl()
    if not url then
      hs.alert.show("Not in Safari")
      return
    end

    local path = url:match("https?://[^/]+(.*)")
    if not path then path = "/" end

    local newUrl = protocol .. "://" .. domain .. path
    setSafariUrl(newUrl)
    hs.alert.show("→ " .. domain)
  end
end

-- Example bindings (customize these):
-- hs.hotkey.bind({"cmd", "alt", "ctrl"}, "1", swapToDomain("localhost:3000", "http"))
-- hs.hotkey.bind({"cmd", "alt", "ctrl"}, "2", swapToDomain("staging.example.com"))
-- hs.hotkey.bind({"cmd", "alt", "ctrl"}, "3", swapToDomain("example.com"))

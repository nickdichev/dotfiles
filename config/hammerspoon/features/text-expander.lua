-- Trie-based text snippet expansion.
-- Type a trigger (e.g. ";date") followed by Space or Return to expand.

local snippets = {
  [";date"] = function()
    return os.date("%B %d, %Y")
  end,
  [";time"] = function()
    return os.date("%H:%M")
  end,
  -- Add your own snippets:
  -- [";email"] = "you@example.com",
  -- [";meet"] = "https://zoom.us/j/your-meeting-id",
}

-- Build a trie for efficient prefix matching
local function buildTrie(snippetTable)
  local trie = {}
  for trigger, expansion in pairs(snippetTable) do
    local node = trie
    for i = 1, #trigger do
      local char = trigger:sub(i, i)
      if not node[char] then
        node[char] = {}
      end
      node = node[char]
    end
    node["_expansion"] = expansion
  end
  return trie
end

local trie = buildTrie(snippets)
local currentNode = trie
local typedLength = 0

-- Keycode-to-char mapping for shifted keys
local shiftedMap = {
  ["1"] = "!", ["2"] = "@", ["3"] = "#", ["4"] = "$", ["5"] = "%",
  ["6"] = "^", ["7"] = "&", ["8"] = "*", ["9"] = "(", ["0"] = ")",
  ["-"] = "_", ["="] = "+", ["["] = "{", ["]"] = "}", ["\\"] = "|",
  [";"] = ":", ["'"] = '"', [","] = "<", ["."] = ">", ["/"] = "?",
  ["`"] = "~",
}

-- Reverse map for typing: special char -> {key, shifted}
local typeMap = {}
for base, shifted in pairs(shiftedMap) do
  typeMap[shifted] = { key = base, shift = true }
end

local function typeChar(char)
  local mapping = typeMap[char]
  if mapping then
    hs.eventtap.keyStroke({ "shift" }, mapping.key, 0)
  elseif char:match("%u") then
    hs.eventtap.keyStroke({ "shift" }, char:lower(), 0)
  else
    hs.eventtap.keyStroke({}, char, 0)
  end
end

local function typeString(str)
  for i = 1, #str do
    typeChar(str:sub(i, i))
  end
end

local function resetState()
  currentNode = trie
  typedLength = 0
end

local function getExpansion(node)
  local expansion = node["_expansion"]
  if type(expansion) == "function" then
    return expansion()
  end
  return expansion
end

local expander = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
  local keyCode = event:getKeyCode()
  local flags = event:getFlags()

  -- Ignore modifier-only or Cmd/Ctrl combos
  if flags.cmd or flags.ctrl or flags.alt then
    resetState()
    return false
  end

  local char = hs.keycodes.map[keyCode]
  if not char then
    resetState()
    return false
  end

  -- Handle shifted characters
  if flags.shift then
    char = shiftedMap[char] or (char:upper())
  end

  -- Space or Return triggers expansion
  if char == "space" or char == "return" then
    if currentNode and currentNode["_expansion"] then
      local expansion = getExpansion(currentNode)
      -- Delete the typed trigger
      for _ = 1, typedLength do
        hs.eventtap.keyStroke({}, "delete", 0)
      end
      -- Type the expansion
      typeString(expansion)
      resetState()
      -- Let the space/return through
      return false
    end
    resetState()
    return false
  end

  -- Walk the trie
  if currentNode[char] then
    currentNode = currentNode[char]
    typedLength = typedLength + 1
    return false
  end

  -- No match, reset
  resetState()
  -- Check if this char starts a new sequence
  if trie[char] then
    currentNode = trie[char]
    typedLength = 1
  end

  return false
end)

expander:start()

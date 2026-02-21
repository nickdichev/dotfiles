-- Sync search patterns between ripgrep and neovim
-- Based on: https://gist.github.com/coxley/b9618b90196c33fc63d5c9b19aa236ee

local path = vim.fn.expand("~/.local/share/last-search")

local function last_search()
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function update_search(term)
  local file, err = io.open(path, "wb")
  if not file then
    vim.notify("failed to open last-search file: " .. err, vim.log.levels.WARN)
  else
    file:write(term)
    file:close()
  end
end

-- Write search pattern to file when leaving search command line
vim.api.nvim_create_autocmd("CmdlineLeave", {
  pattern = { "/", "?" },
  callback = function()
    update_search(vim.fn.getreg("/"))
  end,
})

-- Load last search pattern on startup
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local last_term = last_search()
    if last_term then
      vim.opt.hlsearch = false
      vim.fn.setreg("/", last_term)
      vim.opt.hlsearch = true
    end
  end,
})

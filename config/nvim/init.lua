-- Setup lazy
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Leader
-- Must be done before lazy is loaded
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

-- Point lazy at our plugins module
require('lazy').setup('plugins')

require('lsp')
require('options')
require('completion')
require('keybinds')

-- require('plugin/gitsigns')
-- require('plugin/lazygit')
-- require('plugin/onedark')
-- require('plugin/lualine')
-- require('plugin/elixir')

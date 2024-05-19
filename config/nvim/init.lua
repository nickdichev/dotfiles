-- Leader
-- Must be done before lazy is loaded
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

require('plugins')
require('lsp')
require('options')
require('completion')
require('keybinds')

require('plugin/gitsigns')
require('plugin/lazygit')
require('plugin/onedark')
require('plugin/lualine')

require('plugin/elixir')

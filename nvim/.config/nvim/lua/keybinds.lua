local function map(mode, lhs, rhs, opts)
  local options = {noremap = true}
  if opts then options = vim.tbl_extend('force', options, opts) end
  vim.keymap.set(mode, lhs, rhs, options)
end

-- Leader
vim.g.mapleader = ' '

-- Telescope
local telescope_builtin = require('telescope.builtin')
map('n', '<leader>ff', telescope_builtin.find_files)
map('n', '<leader>fr', telescope_builtin.live_grep)
map('n', '<leader>fb', telescope_builtin.buffers)
map('n', '<leader>fc', telescope_builtin.grep_string)
map('n', '<leader>fh', telescope_builtin.help_tags)

-- Lazygit
map('n', '<leader>gg', ':LazyGit<CR>')

-- Resize splits
map('n', '<Up>', 'resize +2<CR>')
map('n', '<Down>', 'resize -2<CR>')
map('n', '<Left>', 'vertical resize +2<CR>')
map('n', '<Right>', 'vertical resize -2<CR>')

-- Move between splits
map('n', '<leader>h', '<C-W>h')
map('n', '<leader>j', '<C-W>j')
map('n', '<leader>k', '<C-W>k')
map('n', '<leader>l', '<C-W>l')

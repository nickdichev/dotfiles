local opt = vim.opt

opt.encoding = 'UTF-8'

opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.signcolumn = 'yes:1'

opt.shiftwidth = 2
opt.autoindent = true
opt.smartindent = true

opt.tabstop = 2
opt.softtabstop = 2
opt.expandtab = true

opt.splitbelow = true
opt.splitright = true

-- TODO: trailing whitespace
-- opt.list = true
-- opt.listchars:append({tab = '·'})
-- opt.listchars:append({trail = '·'})

opt.scrolloff = 15

opt.termguicolors = true

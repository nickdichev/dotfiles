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

return require('lazy').setup({
  'lewis6991/gitsigns.nvim',
  'kdheepak/lazygit.nvim',
  'tpope/vim-eunuch',
  'tpope/vim-surround',
  'tpope/vim-projectionist',
  'andymass/vim-matchup',
  'mhinz/vim-sayonara',
  {'christoomey/vim-tmux-navigator', lazy = false },

  'navarasu/onedark.nvim',
  'nvim-lualine/lualine.nvim',

  'neovim/nvim-lspconfig',
  'nvim-treesitter/nvim-treesitter-context',
  'nvim-treesitter/nvim-treesitter-textobjects',
  { 'nvim-treesitter/nvim-treesitter', build = ':TSUpdate' },

  'hrsh7th/cmp-nvim-lsp',
  'hrsh7th/cmp-buffer',
  'hrsh7th/cmp-path',
  'hrsh7th/cmp-cmdline',
  'hrsh7th/nvim-cmp',
  'hrsh7th/cmp-vsnip',
  'hrsh7th/vim-vsnip',

  { 'nvim-telescope/telescope.nvim', dependencies = { {'nvim-lua/plenary.nvim'} } },
  { 'elixir-tools/elixir-tools.nvim', dependencies = { 'nvim-lua/plenary.nvim' } },
})

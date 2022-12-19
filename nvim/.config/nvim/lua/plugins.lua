return require('packer').startup(function(use)
  use 'wbthomason/packer.nvim'
  use 'nvim-lua/plenary.nvim'
  use 'lewis6991/gitsigns.nvim'
  use 'kdheepak/lazygit.nvim'
  use 'tpope/vim-eunuch'
  use 'tpope/vim-commentary'
  use 'tpope/vim-surround'
  use 'tpope/vim-projectionist'
  use 'andymass/vim-matchup'

  use 'navarasu/onedark.nvim'
  use 'nvim-lualine/lualine.nvim'

  use 'neovim/nvim-lspconfig'
  use 'nvim-treesitter/nvim-treesitter-context'
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }

  use 'hrsh7th/cmp-nvim-lsp'
  use 'hrsh7th/cmp-buffer'
  use 'hrsh7th/cmp-path'
  use 'hrsh7th/cmp-cmdline'
  use 'hrsh7th/nvim-cmp'
  use 'hrsh7th/cmp-vsnip'
  use 'hrsh7th/vim-vsnip'

  use { 'nvim-telescope/telescope.nvim', tag = '0.1.0', requires = { {'nvim-lua/plenary.nvim'} } }
  use { 'mhanberg/elixir.nvim', requires = { {'nvim-lua/plenary.nvim', opt = true} } }
end)

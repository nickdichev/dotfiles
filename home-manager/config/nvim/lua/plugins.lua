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
  use 'mhinz/vim-sayonara'
  use {'christoomey/vim-tmux-navigator', lazy = false }

  use 'navarasu/onedark.nvim'
  use 'nvim-lualine/lualine.nvim'

  use 'neovim/nvim-lspconfig'
  use 'nvim-treesitter/nvim-treesitter-context'
  use 'nvim-treesitter/nvim-treesitter-textobjects'
  use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
  use { 'jose-elias-alvarez/null-ls.nvim', requires = { 'nvim-lua/plenary.nvim' } }

  use 'hrsh7th/cmp-nvim-lsp'
  use 'hrsh7th/cmp-buffer'
  use 'hrsh7th/cmp-path'
  use 'hrsh7th/cmp-cmdline'
  use 'hrsh7th/nvim-cmp'
  use 'hrsh7th/cmp-vsnip'
  use 'hrsh7th/vim-vsnip'

  use { 'nvim-telescope/telescope.nvim', tag = '0.1.0', requires = { {'nvim-lua/plenary.nvim'} } }

  use { 'elixir-tools/elixir-tools.nvim', requires = { 'nvim-lua/plenary.nvim' } }

  use 'olical/conjure'
  use 'p00f/nvim-ts-rainbow'
  use 'janet-lang/janet.vim'
  use 'jaawerth/fennel.vim'
  use { 'eraserhd/parinfer-rust', run = 'cargo build --release' }
end)

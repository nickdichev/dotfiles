return {
  {'lewis6991/gitsigns.nvim', config = true},
  'kdheepak/lazygit.nvim',
  'tpope/vim-eunuch', -- sugar for unix shell commands
  'tpope/vim-surround',
  'tpope/vim-projectionist',
  'andymass/vim-matchup',
  'mhinz/vim-sayonara',
  {'christoomey/vim-tmux-navigator', lazy = false },

  {'maxmx03/dracula.nvim', config = function ()
    vim.cmd.colorscheme 'dracula'
  end},

  {'nvim-lualine/lualine.nvim', opts = {
    options = {
      theme = vim.g.colors_name,
      refresh = {statusline = 1000}
    }
  }},

  'neovim/nvim-lspconfig',

  'hrsh7th/cmp-nvim-lsp',
  'hrsh7th/cmp-buffer',
  'hrsh7th/cmp-path',
  'hrsh7th/cmp-cmdline',
  'hrsh7th/nvim-cmp',
  'hrsh7th/cmp-vsnip',
  'hrsh7th/vim-vsnip',

  { 'nvim-telescope/telescope.nvim', dependencies = { 'nvim-lua/plenary.nvim' } }
}

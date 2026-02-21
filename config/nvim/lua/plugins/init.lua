return {
  { "lewis6991/gitsigns.nvim", config = true },
  "kdheepak/lazygit.nvim",
  "tpope/vim-eunuch", -- sugar for unix shell commands
  "andymass/vim-matchup",
  "mhinz/vim-sayonara",

  { "nvim-mini/mini.ai", version = "*", opts = {} },
  { "nvim-mini/mini.comment", version = "*", opts = {} },
  { "nvim-mini/mini.surround", version = "*", opts = {} },
  { "nvim-mini/mini.jump", version = "*", opts = {} },
  { "nvim-mini/mini.splitjoin", version = "*", opts = {} },
  { "nvim-mini/mini.files", version = "*", opts = {} },

  {
    "ellisonleao/gruvbox.nvim",
    priority = 1000,
    config = function()
      require("gruvbox").setup({
        terminal_colors = true,
        contrast = "",
      })
      vim.cmd.colorscheme("gruvbox")
    end,
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" }, -- if you use standalone mini plugins
    opts = {},
  },

  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },
}

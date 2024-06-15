return {
  {
    "nvim-treesitter/nvim-treesitter",
    event = "BufRead",
    build = function() vim.cmd("TSUpdate") end,
    dependencies = {
      { "nvim-treesitter/nvim-treesitter-textobjects" },
    },
    config = function ()
      require("nvim-treesitter.install").compilers = { vim.g.gcc_bin_path }
      require("nvim-treesitter.configs").setup {
        ensure_installed = {
          "elixir",
          "erlang",
          "hcl",
          "heex",
          "html",
          "javascript",
          "json",
          "lua",
          "markdown",
          "nix",
          "python",
          "toml",
          "yaml"
        },
        highlight = { enable = true },
        indent    = { enable = true },
        matchup   = { enable = true },
        rainbow   = { enable = true },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,

            keymaps = {
              ["ab"] = "@block.outer",
              ["ib"] = "@block.inner",
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner"
            },

            selection_modes = {
              ['@parameter.outer'] = 'v', -- charwise
              ['@function.outer'] = 'V', -- linewise
              ['@class.outer'] = '<c-v>', -- blockwise
            },

            include_surrounding_whitespace = true,
          },
        }
      }
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "BufRead",
    opts = {
      enable = true,
    },
  },
}

return {
  {
    "zbirenbaum/copilot.lua",
    enabled = true,
    event = "VeryLazy",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        debounce = 75,
      },
      filetypes = {
        yaml = true,
        gitcommit = true,
        markdown = true,
      },
      copilot_node_command = vim.g.nodejs_bin_path,
    },
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    dependencies = {
      { "zbirenbaum/copilot.lua" },
      { "nvim-lua/plenary.nvim" },
    },
    opts = {
      -- See Configuration section for rest
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}

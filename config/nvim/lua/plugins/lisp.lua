return {
  {
    "Olical/conjure",
    ft = { "clojure", "fennel" },
    keys = {
      -- This keymap will now work from the start screen
      { "<leader>cs", "<cmd>ConjureSchool<cr>", desc = "Conjure School" },

      -- You can add other keymaps here that will also lazy-load the plugin
      -- { "<leader>cc", "<cmd>ConjureConnect<cr>", desc = "Conjure Connect" },
    },
    lazy = true,
  },
  {
    "gpanders/nvim-parinfer",
    ft = { "clojure", "fennel" },
    lazy = true,
  },
}

local map = require("core.utils").map

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true }),
  callback = function(event)
    local opts = { buffer = event.buf }

    map("n", "gd", function()
      vim.lsp.buf.definition()
    end, opts)
    map("n", "K", function()
      vim.lsp.buf.hover()
    end, opts)
    map("n", "<leader>vws", function()
      vim.lsp.buf.workspace_symbol()
    end, opts)
    map("n", "<leader>vd", function()
      vim.diagnostic.open_float()
    end, opts)
    map("n", "[d", function()
      vim.diagnostic.jump { count = 1, float = true }
    end, opts)
    map("n", "]d", function()
      vim.diagnostic.jump { count = -1, float = true }
    end, opts)
    map("n", "<leader>vca", function()
      vim.lsp.buf.code_action()
    end, opts)
    map("n", "<leader>vrr", function()
      vim.lsp.buf.references()
    end, opts)
    map("n", "<leader>vrn", function()
      vim.lsp.buf.rename()
    end, opts)
    map("i", "<C-h>", function()
      vim.lsp.buf.signature_help()
    end, opts)
  end,
})

vim.lsp.enable { "ts_ls", "lexical", "lua-language-server", "basedpyright", "nil-ls" }

return {
  {
    "Sebastian-Nielsen/better-type-hover",
    ft = { "typescript", "typescriptreact" },
    config = function()
      require("better-type-hover").setup()
    end,
  },
}

return {
  {
    {
      "rgroli/other.nvim",
      main = "other-nvim",
      opts = {
        mappings = {
          -- Vike page -> data
          {
            pattern = "/interface/(.*)/%+Page.tsx$",
            target = "/interface/%1/+data.ts",
            context = "data",
          },
          -- Vike data -> page
          {
            pattern = "/interface/(.*)/%+data.ts$",
            target = "/interface/%1/+Page.tsx",
            context = "page",
          },
          -- TRPC API -> schema
          {
            pattern = "/interface/controllers/(.*)/(.*).trpc.ts$",
            target = "/interface/controllers/%1/%2.trpc.schema.ts",
            context = "schema",
          },
          "c",
          "livewire",
          "angular",
          "laravel",
          "rails",
          "golang",
          "python",
          "react",
          "rust",
          "elixir",
          "clojure",
        },
        style = {
          width = 0.33,
        },
      },
    },
  },
}

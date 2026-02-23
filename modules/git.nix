{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.git;
  homeDir = config.home.homeDirectory;
in
{
  options.profiles.git.enable = lib.mkEnableOption "Git with difftastic, lazygit, and project-specific identities";

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.git-absorb
    ];

    programs.difftastic = {
      enable = true;
      git.enable = true;
    };

    programs.lazygit = {
      enable = true;
      settings = {
        git = {
          pagers = [
            { externalDiffCommand = "difft --color=always"; }
          ];
        };
      };
    };

    programs.git = {
      enable = true;
      lfs.enable = true;

      settings = {
        user = {
          name = "Nick Dichev";
          email = "git@dichev.email";
        };
        init = {
          defaultBranch = "main";
        };
        column = {
          ui = "auto";
        };
        branch = {
          sort = "-committerdate";
        };
        tag = {
          sort = "version:refname";
        };
        diff = {
          algorithm = "histogram";
          colorMoved = "plain";
          mnemonicPrefix = true;
          renames = true;
        };
        push = {
          default = "simple";
          autoSetupRemote = true;
          followTags = true;
        };
        fetch = {
          prune = true;
          pruneTags = true;
          all = true;
        };
        help = {
          autocorrect = "prompt";
        };
        commit = {
          verbose = true;
        };
        rerere = {
          enabled = true;
          autoupdate = true;
        };
        rebase = {
          autoSquash = true;
          autoStash = true;
          updateRefs = true;
        };
        aliases = { };
      };

      ignores = [
        ".elixir_ls"
        ".elixir-tools"
        ".rgignore"
        ".fzfignore"
        ".envrc"
        ".DS_Store"
        ".direnv"
        ".claude/settings.local.json"
      ];

      # Conditional includes for per-project identity overrides
      # Using gitdir/i for case-insensitive matching (macOS friendly)
      includes = [
        {
          condition = "hasconfig:remote.*.url:git@github.com/Portal-Wholesale/**";
          contents.user = {
            email = "nick@portalwholesale.com";
          };
        }
        {
          condition = "hasconfig:remote.*.url:git@github.com/VenueGo/**";
          contents.user = {
            email = "nick@venuego.io";
          };
        }
        {
          condition = "hasconfig:remote.*.url:git@git.clan.lol/**";
          contents.user = {
            email = "clan@dichev.email";
          };
        }
      ];
    };

  };
}

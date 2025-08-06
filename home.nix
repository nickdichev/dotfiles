{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./username.nix
    ./git.nix
  ];

  home.stateVersion = "22.11"; # Please read the comment before changing.

  home.packages = [
    pkgs.aider-chat
    pkgs.bitwarden-desktop
    pkgs.claude-code
    pkgs.curl
    pkgs.devenv
    pkgs.fd
    pkgs.graphviz
    pkgs.git-absorb
    pkgs.htop
    pkgs.lazydocker
    pkgs.lolcat
    pkgs.inetutils
    pkgs.imagemagick
    pkgs.ffmpeg
    pkgs.mediainfo
    pkgs.nerd-fonts.fira-code
    pkgs.obsidian
    pkgs.ripgrep
    pkgs.tailscale
    pkgs.uv
    pkgs.viddy
    pkgs.wget
    pkgs.windsurf

    (pkgs.python312.withPackages (ps: [
      ps.llm
      ps.llm-cmd
    ]))

    (pkgs.callPackage ./scripts/listening.nix { })
    (pkgs.callPackage ./scripts/clean_git_branches.nix { })
  ]
  ++ lib.optionals (pkgs.stdenv.isDarwin) [
    pkgs.aerospace
    (pkgs.tableplus.overrideAttrs (oldAttrs: rec {
      version = "624";
      src = pkgs.fetchurl {
        url = "https://files.tableplus.com/macos/${version}/TablePlus.dmg";
        hash = "sha256-16fGt2LbB2VlwctkCpXlwRawmTEjOHwg844DqAhQJlc=";
      };
    }))
    pkgs.raycast
  ];

  home.file = {
    ".psql" = {
      source = ./config/psql;
    };
  };

  home.sessionVariables = {
    # ELIXIR_EDITOR = "kitty @ launch --title Output --keep-focus nvim +__LINE__ __FILE__";
    ERL_AFLAGS = "-kernel shell_history enabled";
  };

  programs.home-manager.enable = true;

  programs.bat = {
    enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type file --color=always";
    defaultOptions = [ "--ansi" ];
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.eza = {
    enable = true;
    git = true;
    icons = "auto";
  };

  programs.tealdeer = {
    enable = true;
  };

  programs.lazygit = {
    enable = true;
    settings = {
      git.paging = {
        externalDiffCommand = "difft --color=always";
      };
    };
  };

  programs.gh = {
    enable = true;
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      username = {
        format = "[$user]($style)@";
        show_always = true;
      };
      hostname = {
        format = "[$hostname]($style) in ";
        ssh_only = false;
        style = "bold yellow";
      };
      character = {
        success_symbol = "[~>](bold green)";
        error_symbol = "[~>](bold red)";
      };
      elixir = {
        format = "[$version OTP $otp_version]($style) ";
        style = "bold red";
      };
      nix_shell = {
        disabled = true;
      };
      package = {
        disabled = true;
      };
      gcloud.disabled = true;
      aws.disabled = true;
      custom = {
        bw-locked = {
          command = "echo 🔒";
          when = "! rbw unlocked";
        };
      };
    };
  };

  programs.jq = {
    enable = true;
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    difftastic.enable = true;

    extraConfig = {
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
    };

    aliases = { };

    ignores = [
      ".elixir_ls"
      ".elixir-tools"
      ".rgignore"
      ".fzfignore"
      ".envrc"
      ".DS_Store"
      ".direnv"
    ];
  };

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";
    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;

    initContent = ''
      bindkey -e

      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; 
      then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi

      eval "$(ssh-agent -s)"
      ssh-add ~/.ssh/github

      export HISTORY_FILTER_EXCLUDE=("_KEY" "Bearer" "_TOKEN")
    '';

    shellAliases = {
      ls = "eza";
      la = "eza -a";
      ll = "eza -l";
      lt = "eza --tree";
      lla = "eza -la";

      ".." = "cd ..";
      "..2" = "cd ../..";
      "..3" = "cd ../../..";
      "..4" = "cd ../../../..";
      "..5" = "cd ../../../../..";

      ga = "git add";
      gap = "git add -p";
      gb = "git branch";
      gbc = "git branch --show-current | tr -d '\n' | pbcopy";
      gc = "git commit";
      gcm = "git commit -m";
      gco = "git checkout";
      gcob = "git checkout -b";
      gf = "git fetch";
      glc = "git log --oneline | cut -d\" \" -f 1 | head -n 1";
      glcm = "git log --oneline | cut -d\" \" -f 2- | head -n 1";
      glo = "git log --oneline";
      gp = "git push";
      gpf = "git push --force-with-lease";
      gpsu = "git push --set-upstream origin HEAD";
      gra = "git rebase --abort";
      grc = "git rebase --continue";
      grhh = "git reset --hard HEAD";
      gri = "git rebase -i";
      gs = "git status";
      gsw = "git switch";

      vim = "nvim";
      watch = "viddy";
      lis = "listening";
    };

    plugins = [
      {
        name = "zsh-completions";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-completions";
          rev = "0.35.0";
          sha256 = "GFHlZjIHUWwyeVoCpszgn4AmLPSSE8UVNfRmisnhkpg=";
        };
      }

      {
        name = "zsh-syntax-highlighting";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-syntax-highlighting";
          rev = "0.8.0";
          sha256 = "iJdWopZwHpSyYl5/FQXEW7gl/SrKaYDEtTH9cGP7iPo=";
        };
      }

      {
        name = "zsh-history-filter";
        src = pkgs.fetchFromGitHub {
          owner = "MichaelAquilina";
          repo = "zsh-history-filter";
          rev = "0.4.1";
          sha256 = "sha256-OlGaBRD5F9z2WmhNp7nhs0B9mW4cLkkGeMYZq81uy44=";
        };
      }
    ];
  };

  programs.zellij = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zed-editor = {
    enable = true;
    extensions = [
      "elixir"
      "nix"
    ];
    userSettings = {
      vim_mode = true;

      assistant = {
        version = "2";
        default_model = {
          provider = "anthropic";
          model = "claude-3-5-sonnet-latest";
        };
      };
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraPackages = [
      # Tools
      pkgs.gcc
      pkgs.nodejs
      pkgs.tree-sitter

      # Formatting
      pkgs.black
      pkgs.isort
      pkgs.nixfmt-rfc-style
      pkgs.nodePackages.eslint
      pkgs.prettierd
      pkgs.shfmt
      pkgs.stylua

      # LSP
      (pkgs.lexical.override { elixir = pkgs.beamMinimal27Packages.elixir_1_17; })
      pkgs.basedpyright
      pkgs.lua-language-server
      pkgs.nil
      pkgs.typescript-language-server
    ];

  };

  xdg.configFile = {
    "nvim/init.lua".text = # lua
      ''
        vim.g.gcc_bin_path = '${lib.getExe pkgs.gcc}'
        vim.g.nodejs_bin_path = '${lib.getExe pkgs.nodejs}'
        require("config")
      '';

    "nvim/lua".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/nvim/lua";

    "nvim/lsp".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/nvim/lsp";

    "zellij/config.kdl".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/zellij/config.kdl";

    "zellij/layouts/".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/zellij/layouts";

    "aerospace/aerospace.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/aerospace/config.toml";

    "mcphub/mcpservers.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/mcphub/mcpservers.json";
  };

  programs.atuin = {
    enable = true;
    flags = [ "--disable-up-arrow" ];
    settings = {
      filter_mode_shell_up_key_binding = "session";
      history_filter = [ "^export .*_API_KEY" ];
    };
  };

  programs.mpv = {
    enable = true;
  };

  programs.rbw = {
    enable = true;
    settings = {
      email = "bitwarden@dichev.email";
      pinentry = pkgs.pinentry_mac;
    };
  };

  services.ollama = {
    enable = true;
  };
}

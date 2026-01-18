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
    pkgs.age
    pkgs.attic-client
    pkgs.bitwarden-desktop
    pkgs.claude-code
    pkgs.curl
    pkgs.devenv
    pkgs.fd
    pkgs.ffmpeg
    pkgs.fh
    pkgs.git-absorb
    pkgs.graphviz
    pkgs.htop
    pkgs.imagemagick
    pkgs.inetutils
    pkgs.lazydocker
    pkgs.lolcat
    pkgs.mediainfo
    pkgs.nerd-fonts.fira-code
    pkgs.obsidian
    pkgs.ripgrep
    pkgs.sops
    pkgs.tailscale
    pkgs.uv
    pkgs.viddy
    pkgs.wget

    # (pkgs.python312.withPackages (ps: [
    #   ps.llm
    #   ps.llm-cmd
    # ]))

    (pkgs.callPackage ./scripts/listening.nix { })
    (pkgs.callPackage ./scripts/clean_git_branches.nix { })
  ]
  ++ lib.optionals (pkgs.stdenv.isDarwin) [
    (pkgs.tableplus.overrideAttrs (oldAttrs: rec {
      version = "654";
      src = pkgs.fetchurl {
        url = "https://files.tableplus.com/macos/${version}/TablePlus.dmg";
        hash = "sha256-ROI0a+PtIuqO90mCXzdlMen3PivzI9wjNku7Sn9DhGQ=";
      };
    }))
    pkgs.raycast
    pkgs.hammerspoon
  ];

  home.file = {
    ".psql" = {
      source = ./config/psql;
    };
  };

  xdg.enable = true;

  home.sessionVariables = {
    # ELIXIR_EDITOR = "kitty @ launch --title Output --keep-focus nvim +__LINE__ __FILE__";
    ERL_AFLAGS = "-kernel shell_history enabled";
  };

  programs.home-manager = {
    enable = true;
  };

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
    nix-direnv.enable = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    git = true;
    icons = "auto";
    extraOptions = [ "--group-directories-first" ];
  };

  programs.tealdeer = {
    enable = true;
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

  programs.difftastic = {
    enable = true;
    git.enable = true;
  };

  programs.git = {
    enable = true;
    lfs.enable = true;

    settings = {
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
    ];
  };

  programs.zsh = {
    enable = true;
    dotDir = "${config.home.homeDirectory}/.config/zsh";
    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;

    initContent = ''
      bindkey -e

      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ];
      then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi

      export HISTORY_FILTER_EXCLUDE=("_KEY" "Bearer" "_TOKEN")

      # SSH agent setup (silent)
      eval "$(ssh-agent -s)" > /dev/null 2>&1

      load_ssh_keys() {
        local reset=$'\e[0m'
        local dim=$'\e[2m'
        local bold=$'\e[1m'
        local green=$'\e[32m'
        local yellow=$'\e[33m'
        local red=$'\e[31m'

        echo ""
        echo "  ''${bold}''${yellow}SSH Keys''${reset}"
        echo "  ''${dim}────────────────────────────────────────────''${reset}"

        local keys=(
          "${config.home.homeDirectory}/.ssh/personal/github"
          "${config.home.homeDirectory}/.ssh/personal/forgejo"
          "${config.home.homeDirectory}/.ssh/portal/prod-hetzner"
        )

        for key in "''${keys[@]}"; do
          local name=$(basename "$key")
          if ssh-add "$key" 2>/dev/null; then
            echo "  ''${green}✓''${reset} ''${dim}$name''${reset}"
          else
            echo "  ''${red}✗''${reset} ''${dim}$name (failed)''${reset}"
          fi
        done
        echo ""
      }
      load_ssh_keys

      # Message of the day - Shell hotkeys
      motd() {
        local reset=$'\e[0m'
        local dim=$'\e[2m'
        local bold=$'\e[1m'
        local cyan=$'\e[36m'
        local yellow=$'\e[33m'
        local blue=$'\e[34m'

        local key="''${bold}''${cyan}"
        local desc="''${dim}"
        local sep="''${blue}│''${reset}"

        echo "  ''${bold}''${yellow}Shell Hotkeys''${reset} ''${dim}(emacs mode)''${reset}"
        echo "  ''${dim}────────────────────────────────────────────''${reset}"
        echo "  ''${key}^A''${reset} ''${desc}line start''${reset}    $sep  ''${key}^E''${reset} ''${desc}line end''${reset}    $sep  ''${key}^L''${reset} ''${desc}clear''${reset}"
        echo "  ''${key}^B''${reset} ''${desc}char back''${reset}     $sep  ''${key}^F''${reset} ''${desc}char fwd''${reset}    $sep  ''${key}^R''${reset} ''${desc}history search''${reset}"
        echo "  ''${key}M-B''${reset} ''${desc}word back''${reset}    $sep  ''${key}M-F''${reset} ''${desc}word fwd''${reset}   $sep  ''${key}^Y''${reset} ''${desc}yank''${reset}"
        echo "  ''${key}^U''${reset} ''${desc}kill left''${reset}     $sep  ''${key}^K''${reset} ''${desc}kill right''${reset}  $sep  ''${key}^W''${reset} ''${desc}kill word''${reset}"
        echo ""
      }
      motd
    '';

    shellAliases = {
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

      gg = "lazygit";
      gd = "lazydocker";

      dup = "devenv up";
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

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraPackages = [
      # Tools
      pkgs.gcc
      pkgs.nodejs
      pkgs.tree-sitter

      # Formatting
      pkgs.biome
      pkgs.black
      pkgs.isort
      pkgs.nixfmt
      pkgs.shfmt
      pkgs.sqruff
      pkgs.stylua
      pkgs.oxlint
      pkgs.oxfmt

      # LSP
      pkgs.basedpyright
      pkgs.clojure-lsp
      pkgs.lua-language-server
      pkgs.nil
      pkgs.typescript-language-server
      pkgs.tofu-ls
      pkgs.postgres-language-server
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

    "zellij/config.kdl".source = pkgs.replaceVars ./config/zellij/config.kdl {
      certDir = "${config.home.homeDirectory}/.certs";
      certName = "buckwheat+2";
    };

    "zellij/layouts/".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/zellij/layouts";

    "ghostty/shaders".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/ghostty/shaders";

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
    enable = false;
  };

  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty-bin;
    settings = {
      custom-shader = [
        "${config.home.homeDirectory}/.config/ghostty/shaders/cursor_dracula.glsl"
      ];

      auto-update = "off";
    };
  };

  programs.claude-code = {
    enable = true;
    commandsDir = ./config/claude/commands;
  };
}

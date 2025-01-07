{
  config,
  pkgs,
  lib,
  ...
}:

let
  fireworkConfigPath = ./firework.nix;
  isFireworkMachine = builtins.pathExists (toString fireworkConfigPath);
in
{
  imports = [
    ./username.nix
    ./git.nix
  ] ++ lib.optional isFireworkMachine fireworkConfigPath;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "22.11"; # Please read the comment before changing.

  home.packages = [
    pkgs.aerospace
    pkgs.curl
    pkgs.devenv
    pkgs.fd
    pkgs.graphviz
    pkgs.git-absorb
    pkgs.htop
    pkgs.lolcat
    pkgs.inetutils
    pkgs.mediainfo
    pkgs.ffmpeg
    pkgs.nerd-fonts.fira-code
    pkgs.ripgrep
    pkgs.wget
    pkgs.viddy

    (pkgs.callPackage ./scripts/listening.nix { })
    (pkgs.callPackage ./scripts/clean_git_branches.nix { })
  ];

  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';

    ".psql" = {
      source = ./config/psql;
    };
  };

  home.sessionVariables = {
    # ELIXIR_EDITOR = "kitty @ launch --title Output --keep-focus nvim +__LINE__ __FILE__";
    ERL_AFLAGS = "-kernel shell_history enabled";
  };

  # Let Home Manager install and manage itself.
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

  programs.kitty = {
    enable = false;
    themeFile = "Dracula";
    environment = {
      "KITY_LISTEN_ON" = "unix:/tmp/kitty-$PPID";
    };
    settings = {
      "allow_remote_control" = "yes";
      "listen_on" = "unix:/tmp/kitty";
      "confirm_os_window_on_close" = 1;
    };
    font = {
      name = "Fira Code Nerd Font";
    };
    keybindings = {
      "ctrl+shift+o" = "close_other_windows_in_tab";
      "cmd+t" = "new_tab_with_cwd";
    };
  };

  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
    extraConfig = ''
      local wezterm = require 'wezterm';
      return {
        color_scheme = "Dracula (Official)",
        font = wezterm.font("Fira Code"),
        hide_tab_bar_if_only_one_tab = true,
        front_end = "WebGpu",
      }
    '';
  };

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";
    autocd = true;
    autosuggestion.enable = true;
    enableCompletion = true;

    initExtra = ''
      bindkey -e

      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; 
      then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi

      eval "$(ssh-agent -s)"
      ssh-add ~/.ssh/github
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

      # Fix 256color
      tmux = "tmux -2";
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
    ];
  };

  programs.zellij = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.tmux = {
    enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    keyMode = "vi";
    historyLimit = 100000;
    baseIndex = 0;
    prefix = "C-Space";

    plugins = with pkgs.tmuxPlugins; [
      better-mouse-mode
      sensible
      vim-tmux-navigator
      yank
    ];

    extraConfig = ''
      set -g mouse on

      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
    '';
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    extraPackages = [
      # Tools
      pkgs.gcc
      pkgs.tree-sitter
      pkgs.nodejs

      # Formatting
      pkgs.nixfmt-rfc-style # Nix
      pkgs.black # Python
      pkgs.isort # Python
      pkgs.prettierd # Multi-language
      pkgs.shfmt # Shell
      pkgs.stylua # Lua

      # LSP
      pkgs.lexical
      pkgs.nil
      pkgs.pyright
      pkgs.lua-language-server
      # pkgs.nodePackages."@astrojs/language-server"
      pkgs.nodePackages.eslint
      pkgs.prettierd
      pkgs.gopls
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

    "zellij/config.kdl".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/zellij/config.kdl";

    "aerospace/aerospace.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/aerospace/config.toml";
  };

  programs.atuin = {
    enable = true;
    flags = [ "--disable-up-arrow" ];
    settings = {
      filter_mode_shell_up_key_binding = "session";
    };
  };

  programs.mpv = {
    enable = false;
  };
}

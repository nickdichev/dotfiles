{
  config,
  pkgs,
  aider-pkgs,
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

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for ezample, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For ezample, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    pkgs.curl
    pkgs.devenv
    pkgs.fd
    pkgs.graphviz
    pkgs.htop
    pkgs.lolcat
    pkgs.inetutils
    pkgs.mediainfo
    pkgs.ffmpeg-full
    # https://github.com/NixOS/nixpkgs/blob/nixos-22.11/pkgs/data/fonts/nerdfonts/shas.nix
    (pkgs.nerdfonts.override { fonts = [ "FiraCode" ]; })
    pkgs.ripgrep
    pkgs.wget
    pkgs.viddy
    aider-pkgs.aider-chat

    (pkgs.writeShellScriptBin "listening" ''
      #!/bin/sh

       if [[ $# -eq 0 ]]; then
         lsof -iTCP -sTCP:LISTEN -n -P
       elif [[ $# -eq 1 ]]; then
         lsof -iTCP -sTCP:LISTEN -n -P | rg -i "$1"
       else
         echo "Usage: listening [port]"
         exit 1
       fi
    '')
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
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

  # You can also manage environment variables but you will have to manually
  # source
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/kamana/etc/profile.d/hm-session-vars.sh
  #
  # if you don't want to manage your shell through Home Manager.
  home.sessionVariables = {
    ELIXIR_EDITOR = "kitty @ launch --title Output --keep-focus nvim +__LINE__ __FILE__";
    ERL_AFLAGS = "-kernel shell_history enabled";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  programs.bat = {
    enable = true;
  };

  programs.fzf = {
    enable = true;
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
    icons = true;
  };

  programs.tealdeer = {
    enable = true;
  };

  programs.lazygit = {
    enable = true;
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

    extraConfig = {
      init = {
        defaultBranch = "main";
      };
      merge = {
        conflictStyle = "diff3";
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
      ".aider*"
    ];

    delta = {
      enable = true;
    };
  };

  programs.kitty = {
    enable = true;
    theme = "Dracula";
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

    # initExtra = lib.strings.concatLines [ "bindkey -e" ];
    initExtra = ''
      bindkey -e

      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; 
      then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
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
      pkgs.prettierd # Multi-language
      pkgs.shfmt # Shell
      pkgs.isort # Python
      pkgs.stylua # Lua

      # LSP
      pkgs.lexical
      pkgs.nil
      pkgs.pyright
      pkgs.lua-language-server
      pkgs.nodePackages."@astrojs/language-server"
      pkgs.nodePackages.eslint
      pkgs.prettierd
    ];

  };

  xdg.configFile = {
    "nvim/init.lua".text = # lua
      ''
        vim.g.gcc_bin_path = '${lib.getExe pkgs.gcc}'
        vim.g.nodejs_bin_path = '${lib.getExe pkgs.nodejs}'
        require("config")
      '';

    "nvim/lua".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.config/home-manager/config/nvim/lua";
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

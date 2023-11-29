{ config, pkgs, lib, ... }:

let
  fireworkConfigPath = ./firework.nix;
  isFireworkMachine = builtins.pathExists (toString fireworkConfigPath);
in
{
  imports =
    [./username.nix]
    ++ lib.optional isFireworkMachine fireworkConfigPath;

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

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    pkgs.curl
    pkgs.fd
    pkgs.graphviz
    pkgs.htop
    pkgs.lolcat
    pkgs.inetutils
    pkgs.neovim
    # https://github.com/NixOS/nixpkgs/blob/nixos-22.11/pkgs/data/fonts/nerdfonts/shas.nix
    (pkgs.nerdfonts.override { fonts = [ "FiraCode" ]; })
    pkgs.ripgrep
    pkgs.wget
    pkgs.viddy

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

    ".psql"  =  {
      source = ./config/psql;
    };

    ".nvim"  =  {
      source = ./config/nvim;
      target = ".config/nvim";
      recursive = true;
    };

    ".hammerspoon" = {
      source = ./config/hammerspoon;
      recursive = true;
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
    EDITOR = "nvim";

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
    defaultOptions = ["--ansi"];
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
  };

  programs.jq = {
    enable = true;
  };

  programs.git = {
    enable = true;
    lfs.enable = true;

    userEmail = "github@dichev.email";
    userName = "Nick Dichev";

    extraConfig = {
      init = {
        defaultBranch = "main";
      };
      merge = {
        conflictStyle = "diff3";
      };
    };

    aliases = {};

    ignores = [
      ".elixir_ls"
      ".elixir-tools"
      ".rgignore"
      ".fzfignore"
      ".envrc"
      ".DS_Store"
      ".direnv"
    ];

    delta = {
      enable = true;
    };
  };

  programs.kitty = {
    enable = true;
    theme = "Dark One Nuanced";
    environment = {
      "KITY_LISTEN_ON" = "unix:/tmp/kitty-$PPID";
    };
    settings = {
      "allow_remote_control" = "yes";
      "listen_on" = "unix:/tmp/kitty";
      "confirm_os_window_on_close" = 1;
    };
    font = {
      name = "Fira Code";
    };
    keybindings = {
      "ctrl+shift+o" = "close_other_windows_in_tab";
      "cmd+t" = "new_tab_with_cwd";
    };
  };

  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";
    autocd = true;
    enableAutosuggestions = true;
    enableCompletion = true;

    # initExtra = lib.strings.concatLines [ "bindkey -e" ];
    initExtra =  ''
      bindkey -e

      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; 
      then
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
      fi
    '';

    shellAliases = {
      ls = "exa";
      la = "exa -a";
      ll = "exa -l";
      lt = "exa --tree";
      lla = "exa -la";

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

      vim  =  "nvim";
      watch = "viddy";
      lis = "listening";

      preview_file = "fd --no-ignore --hidden --follow --strip-cwd-prefix | fzf --preview \'bat --style=numbers --color=always --line-range :500 {}\'";
      preview_git_commits = "git log --oneline --decorate --color | fzf --preview \'git show $(echo {} | cut -d\" \" -f1) | delta\'";
    };

    plugins = [
      {
        name = "zsh-completions";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-completions";
          rev = "0.27.0";
          sha256 = "1c2xx9bkkvyy0c6aq9vv3fjw7snlm0m5bjygfk5391qgjpvchd29";
        };
      }

      {
        name = "zsh-history-substring-search";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-history-substring-search";
          rev = "47a7d416c652a109f6e8856081abc042b50125f4";
          sha256 = "1mvilqivq0qlsvx2rqn6xkxyf9yf4wj8r85qrxizkf0biyzyy4hl";
        };
      }

      {
        name = "zsh-syntax-highlighting";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-syntax-highlighting";
          rev = "db6cac391bee957c20ff3175b2f03c4817253e60";
          sha256 = "0d9nf3aljqmpz2kjarsrb5nv4rjy8jnrkqdlalwm2299jklbsnmw";
        };
      }

      {
        name = "nix-shell";
        src = pkgs.fetchFromGitHub {
          owner = "chisui";
          repo = "zsh-nix-shell";
          rev = "03a1487655c96a17c00e8c81efdd8555829715f8";
          sha256 = "1avnmkjh0zh6wmm87njprna1zy4fb7cpzcp8q7y03nw3aq22q4ms";
        };
      }
    ];
  };

  programs.tmux = {
    enable = true;
    shell = "${pkgs.zsh}/bin/zsh";
    keyMode = "vi";
    terminal = "screen-256color";
    historyLimit = 100000;
    baseIndex = 1;
    prefix = "C-Space";
    
    plugins = with pkgs; [
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.sensible
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.yank
    ];

    extraConfig = ''
      set-option -sa terminal-overrides ",xterm*:Tc"
      set -g mouse on

      bind-key -T copy-mode-vi v send-keys -X begin-selection
      bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
      bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel
    '';
  };

  programs.atuin = {
    enable = true;
    flags = [
      "--disable-up-arrow"
    ];
    settings = {
      filter_mode_shell_up_key_binding = "session";
    };
  };

}

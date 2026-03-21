{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.utils;
  pkgs-unstable = import inputs.nixpkgs-unstable { inherit (pkgs) system; };
in
{
  options.profiles.utils.enable = lib.mkEnableOption "Utility programs (bat, fzf, eza, ripgrep, etc.)";

  config = lib.mkIf cfg.enable {
    home.file.".psqlrc".text = ''
      \set QUIET 1
      \pset null 👻
      \set HISTFILE ~/.psql_history- :DBNAME

      \pset border 2
      \pset linestyle unicode
      \unset QUIET
    '';

    home.packages = [
      pkgs.bkt
      pkgs.curl
      pkgs.fd
      pkgs.graphviz
      # pkgs.inetutils
      pkgs.lazydocker
      pkgs.lolcat
      pkgs.ripgrep
      pkgs.up
      pkgs.viddy
      pkgs.wget
      pkgs-unstable.tailscale
    ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      inputs.zmx.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    programs.bat = {
      enable = true;
      config = {
        theme = "gruvbox-dark";
        style = "plain";
      };
    };

    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
      defaultCommand = "fd --type file --color=always";
      defaultOptions = [ "--ansi" ];
      colors = {
        "bg+" = "#3c3836";
        bg = "#282828";
        spinner = "#8ec07c";
        hl = "#83a598";
        fg = "#bdae93";
        header = "#83a598";
        info = "#fabd2f";
        pointer = "#8ec07c";
        marker = "#8ec07c";
        "fg+" = "#ebdbb2";
        prompt = "#fabd2f";
        "hl+" = "#83a598";
      };
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

    programs.jq = {
      enable = true;
    };
  };
}

{ inputs }:
{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.neovim;
  pkgs-unstable = import inputs.nixpkgs-unstable { inherit (pkgs) system; };
  storeConfigPath = ../config/nvim;
  useSymlink = config.profiles.neovim.configPath != null;
  nvimConfigPath = config.profiles.neovim.configPath;
in
{
  options.profiles.neovim = {
    enable = lib.mkEnableOption "Neovim editor with LSPs and formatters";
    configPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Absolute path to nvim config directory for out-of-store symlink. If null, uses the Nix store copy.";
    };
  };

  config = lib.mkIf cfg.enable {
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
        pkgs-unstable.oxfmt

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

      "nvim/lua".source = if useSymlink
        then config.lib.file.mkOutOfStoreSymlink "${nvimConfigPath}/lua"
        else "${storeConfigPath}/lua";
      "nvim/lsp".source = if useSymlink
        then config.lib.file.mkOutOfStoreSymlink "${nvimConfigPath}/lsp"
        else "${storeConfigPath}/lsp";
    };
  };
}

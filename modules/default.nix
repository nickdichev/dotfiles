{ inputs }:
{ config, lib, pkgs, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  imports = [
    (import ./ai.nix { inherit inputs; })
    (import ./applications.nix { inherit inputs; })
    ./base.nix
    (import ./sesame.nix { inherit inputs; })
    (import ./dev.nix { inherit inputs; })
    ./fonts.nix
    ./git.nix
    ./media-processing.nix
    (import ./neovim.nix { inherit inputs; })
    ./scripts.nix
    ./secrets.nix
    (import ./shell.nix { inherit inputs; })
    ./terminal.nix
    (import ./utils.nix { inherit inputs; })
    ./zellij.nix
  ];

  options.profiles = {
    hasGui = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to install GUI applications. Set by the consuming clan's bridge module.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "nick";
      description = "The username for home.username and home directory path.";
    };
  };

  config = {
    home.username = config.profiles.username;
    home.homeDirectory = lib.mkForce (
      if isDarwin then "/Users/${config.profiles.username}" else "/home/${config.profiles.username}"
    );
  };
}

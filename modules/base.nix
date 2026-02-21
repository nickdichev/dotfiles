{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.base;
in
{
  options.profiles.base.enable = lib.mkEnableOption "Base home-manager configuration (stateVersion, XDG)";

  config = lib.mkIf cfg.enable {
    home.stateVersion = "24.11";
    xdg.enable = true;
  };
}

{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.herdr;
in
{
  options.profiles.herdr.enable = lib.mkEnableOption "Herdr terminal agent multiplexer";

  config = lib.mkIf cfg.enable {
    home.packages = [
      inputs.herdr.packages.${pkgs.system}.default
    ];

    xdg.configFile."herdr/config.toml".source = ../config/herdr/config.toml;
  };
}

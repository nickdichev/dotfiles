{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.fonts;
in
{
  options.profiles.fonts.enable = lib.mkEnableOption "Font packages (Inter, Junicode, Fira Code Nerd Font)";

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.inter
      pkgs.junicode
      pkgs.nerd-fonts.fira-code
    ];
  };
}

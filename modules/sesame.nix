{ inputs }:
{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.sesame;
  sesame = inputs.sesame.packages.${pkgs.system}.default;
in
{
  options.profiles.sesame.enable = lib.mkEnableOption "Clan client tools (sesame)";

  config = lib.mkIf cfg.enable {
    home.packages = [
      sesame
    ];

    programs.zsh.shellAliases = {
      ses = "sesame";
    };
  };
}

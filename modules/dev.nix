{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.dev;
in
{
  options.profiles.dev.enable = lib.mkEnableOption "Development tools (direnv, gh, just)";

  config = lib.mkIf cfg.enable {

    home.packages = [
      pkgs.just
    ];

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;

      config = {
        global = {
          hide_env_diff = true;
        };
      };
    };

    programs.gh = {
      enable = true;
    };

  };
}

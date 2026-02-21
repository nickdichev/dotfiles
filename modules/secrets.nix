{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.secrets;
  hasGui = config.profiles.hasGui;
in
{
  options.profiles.secrets.enable = lib.mkEnableOption "Secret management (age, sops, rbw/Bitwarden)";

  config = lib.mkIf cfg.enable {

    home.packages = [
      pkgs.age
      pkgs.sops
    ]
    ++ lib.optional hasGui pkgs.bitwarden-desktop;

    programs.rbw = {
      enable = true;
      settings = {
        email = "bitwarden@dichev.email";
        pinentry = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-tty;
      };
    };

  };
}

{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.secrets;
  hasGui = config.profiles.hasGui;

  # TODO: Remove this override when Bitwarden Desktop moves off Electron 39.
  # Bitwarden 2026.5.0 declares Electron 39.8.5 upstream; nixpkgs supplies
  # 39.8.10 and marks it EOL. Keep the exception local to Bitwarden instead of
  # permitting electron-39 globally.
  bitwardenDesktop = pkgs.bitwarden-desktop.override {
    electron_39 = pkgs.electron_39.overrideAttrs (old: {
      meta = old.meta // {
        knownVulnerabilities = [ ];
      };
    });
  };
in
{
  options.profiles.secrets.enable = lib.mkEnableOption "Secret management (age, sops, rbw/Bitwarden)";

  config = lib.mkIf cfg.enable {

    home.packages = [
      pkgs.age
      pkgs.sops
    ]
    ++ lib.optional hasGui bitwardenDesktop;

    programs.rbw = {
      enable = true;
      settings = {
        email = "bitwarden@dichev.email";
        pinentry = if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-tty;
      };
    };

  };
}

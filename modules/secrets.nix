{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.secrets;
  hasGui = config.profiles.hasGui;

  # On Darwin, nixpkgs' source-built Bitwarden currently forces an older LLVM
  # stdenv that does not build cleanly against the newer Darwin libc++ headers.
  # Use Bitwarden's official macOS app bundle there, while keeping nixpkgs for
  # platforms where the source build is usable.
  bitwardenDesktop =
    if pkgs.stdenv.isDarwin then
      pkgs.callPackage ../pkgs/bitwarden-desktop-bin { }
    else
      pkgs.bitwarden-desktop;
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

{ inputs }:
{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.applications;
  hasGui = config.profiles.hasGui;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
in
{
  options.profiles.applications.enable = lib.mkEnableOption "Desktop applications (obsidian, raycast, tableplus, rustdesk)";

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      [
      ]
      ++ lib.optionals hasGui [
        pkgs.obsidian
      ]
      ++ lib.optionals (hasGui && isDarwin) [
        (pkgs.tableplus.overrideAttrs (oldAttrs: rec {
          version = "654";
          src = pkgs.fetchurl {
            url = "https://files.tableplus.com/macos/${version}/TablePlus.dmg";
            hash = "sha256-ROI0a+PtIuqO90mCXzdlMen3PivzI9wjNku7Sn9DhGQ=";
          };
        }))

        pkgs-unstable.raycast
        (pkgs.callPackage ../pkgs/rustdesk { })

      ]
      ++ lib.optionals (hasGui && isLinux) [
      ];
  };
}

{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
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
    targets.darwin.defaults = lib.mkIf isDarwin {
      "com.tinyspeck.slackmacgap" = {
        AutoUpdate = false;
      };
    };

    home.packages = [
    ]
    ++ lib.optionals hasGui [
      pkgs.obsidian
      pkgs.slack
      pkgs.telegram-desktop
    ]
    ++ lib.optionals (hasGui && isDarwin) [

      pkgs-unstable.alt-tab-macos
      pkgs-unstable.blackhole
      pkgs-unstable.raycast

      (pkgs.callPackage ../pkgs/rustdesk { })
      (pkgs.callPackage ../pkgs/redisinsight { })
      (pkgs.callPackage ../pkgs/handy { })
      (pkgs.callPackage ../pkgs/pencil { })

      (pkgs.tableplus.overrideAttrs (oldAttrs: rec {
        version = "662";
        src = pkgs.fetchurl {
          url = "https://files.tableplus.com/macos/${version}/TablePlus.dmg";
          hash = "sha256-VR0sSTZfRjjv+p4DcYciKBJG5DHIwj4KLhTHPGRsSX0=";
        };
      }))

    ]
    ++ lib.optionals (hasGui && isLinux) [
      pkgs.redisinsight
    ];
  };
}

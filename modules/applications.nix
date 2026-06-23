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
  options.profiles.applications.enable = lib.mkEnableOption "Desktop applications (obsidian, raycast, tablepro, rustdesk)";

  config = lib.mkIf cfg.enable {
    targets.darwin.defaults = lib.mkIf isDarwin {
      "com.tinyspeck.slackmacgap" = {
        AutoUpdate = false;
        SlackNoAutoUpdates = true;
      };
    };

    home.packages = [
    ]
    ++ lib.optionals hasGui [
      pkgs-unstable.godot
      pkgs.obsidian
      pkgs.slack
      (pkgs-unstable.kdePackages.callPackage ../pkgs/telegram-desktop { })
    ]
    ++ lib.optionals (hasGui && isDarwin) [

      pkgs-unstable.alt-tab-macos
      pkgs-unstable.blackhole
      pkgs-unstable.raycast

      (pkgs.callPackage ../pkgs/rustdesk { })
      (pkgs.callPackage ../pkgs/redisinsight { })
      (pkgs.callPackage ../pkgs/handy { })
      # (pkgs.callPackage ../pkgs/pencil { })
      (pkgs.callPackage ../pkgs/tablepro { })
      (pkgs.callPackage ../pkgs/orcaslicer { })

    ]
    ++ lib.optionals (hasGui && isLinux) [
      pkgs.redisinsight
    ];
  };
}

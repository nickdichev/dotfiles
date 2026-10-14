{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.windowManager;
  hasGui = config.profiles.hasGui;
  isDarwin = pkgs.stdenv.isDarwin;

  # Each tiling WM wants macOS Spaces configured differently, so the settings
  # follow whichever manager is selected instead of living in its module.
  spacesDefaults = {
    aerospace = {
      # AeroSpace emulates its own workspaces and is more stable with one
      # Space spanning all displays; takes effect after logout.
      "com.apple.spaces".spans-displays = true;
      # Keeps Mission Control usable with AeroSpace's hidden windows.
      "com.apple.dock".expose-group-apps = true;
    };
    omniwm = {
      # OmniWM requires "Displays have separate Spaces"; takes effect after logout.
      "com.apple.spaces".spans-displays = false;
      # OmniWM owns workspace order; don't let macOS reshuffle native Spaces.
      "com.apple.dock".mru-spaces = false;
    };
  };
in
{
  imports = [
    ./aerospace.nix
    (import ./omniwm.nix { inherit inputs; })
  ];

  options.profiles.windowManager = {
    manager = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "aerospace"
          "omniwm"
        ]
      );
      default = null;
      description = "Which macOS tiling window manager to run, if any.";
    };
  };

  config = lib.mkIf (cfg.manager != null && hasGui && isDarwin) {
    targets.darwin.defaults = spacesDefaults.${cfg.manager};
  };
}

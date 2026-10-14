{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.windowManager.aerospace;
  hasGui = config.profiles.hasGui;
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  options.profiles.windowManager.aerospace = {
    configPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path to an aerospace.toml to out-of-store symlink into
        ~/.config/aerospace/aerospace.toml. If null, uses the Nix store copy.
      '';
    };
  };

  config = lib.mkIf (config.profiles.windowManager.manager == "aerospace" && hasGui && isDarwin) {
    home.packages = [ pkgs.aerospace ];

    launchd.agents.aerospace = {
      enable = true;
      config = {
        Program = "${pkgs.aerospace}/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
        RunAtLoad = true;
        KeepAlive = true;
        LimitLoadToSessionType = "Aqua";
        ProcessType = "Interactive";
        AssociatedBundleIdentifiers = "bobko.aerospace";
        StandardOutPath = "/tmp/aerospace.log";
        StandardErrorPath = "/tmp/aerospace.err.log";
      };
    };

    xdg.configFile."aerospace/aerospace.toml".source =
      if cfg.configPath != null then
        config.lib.file.mkOutOfStoreSymlink cfg.configPath
      else
        ../../config/aerospace/aerospace.toml;
  };
}

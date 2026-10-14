{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.omniwm;
  hasGui = config.profiles.hasGui;
  isAarch64Darwin = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
  pkgs-unstable = import inputs.nixpkgs-unstable { inherit (pkgs) system; };
  omniwm = pkgs-unstable.omniwm;
in
{
  options.profiles.omniwm = {
    enable = lib.mkEnableOption "OmniWM scrolling/tiling window manager";

    settingsPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Absolute path to an OmniWM settings.toml to out-of-store symlink into
        ~/.config/omniwm/settings.toml. OmniWM writes through symlinks, so GUI
        edits land in the target file. If null, OmniWM manages its own file.
      '';
    };
  };

  # Home Manager's programs.omniwm only exists on master; this mirrors it so
  # consumers on older Home Manager pins can use OmniWM too.
  config = lib.mkIf (cfg.enable && hasGui && isAarch64Darwin) {
    home.packages = [ omniwm ];

    # OmniWM requires "Displays have separate Spaces"; takes effect after logout.
    targets.darwin.defaults."com.apple.spaces".spans-displays = false;

    launchd.agents.omniwm = {
      enable = true;
      config = {
        Program = "${omniwm}/Applications/OmniWM.app/Contents/MacOS/OmniWM";
        RunAtLoad = true;
        KeepAlive = true;
        LimitLoadToSessionType = "Aqua";
        ProcessType = "Interactive";
        AssociatedBundleIdentifiers = "com.barut.OmniWM";
        StandardOutPath = "/tmp/omniwm.log";
        StandardErrorPath = "/tmp/omniwm.err.log";
      };
    };

    xdg.configFile."omniwm/settings.toml" = lib.mkIf (cfg.settingsPath != null) {
      source = config.lib.file.mkOutOfStoreSymlink cfg.settingsPath;
    };
  };
}

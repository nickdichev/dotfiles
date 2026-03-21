{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.hammerspoon;
  hasGui = config.profiles.hasGui;
  isDarwin = pkgs.stdenv.isDarwin;

  vimModeSpoon = pkgs.fetchFromGitHub {
    owner = "dbalatero";
    repo = "VimMode.spoon";
    rev = "a428e1ae9cc5d937fa6d148da6e2a779c7594abd";
    hash = "sha256-C4WDpMVDF0zuDV4rZYx05gwn8YZf3tOGegBj8dma8vY=";
  };
in
{
  options.profiles.hammerspoon = {
    enable = lib.mkEnableOption "Hammerspoon macOS automation";

    configPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Absolute path to hammerspoon config directory for out-of-store symlink. If null, uses the Nix store copy.";
    };
  };

  config = lib.mkIf (cfg.enable && hasGui && isDarwin) {
    home.packages = [
      (pkgs.callPackage ../pkgs/hammerspoon { })
    ];

    # Point Hammerspoon at ~/.config/hammerspoon/init.lua
    targets.darwin.defaults."org.hammerspoon.Hammerspoon" = {
      MJConfigFile = "~/.config/hammerspoon/init.lua";
    };

    xdg.configFile =
      let
        storeConfigPath = ../config/hammerspoon;
        useSymlink = cfg.configPath != null;
        symlink = path: config.lib.file.mkOutOfStoreSymlink "${cfg.configPath}/${path}";
      in
      {
        "hammerspoon/init.lua".source =
          if useSymlink then symlink "init.lua" else "${storeConfigPath}/init.lua";
        "hammerspoon/features".source =
          if useSymlink then symlink "features" else "${storeConfigPath}/features";
        "hammerspoon/spoons/VimMode.spoon".source = vimModeSpoon;
      };
  };
}

{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.terminal;
  hasGui = config.profiles.hasGui;
in
{
  options.profiles.terminal.enable = lib.mkEnableOption "Ghostty terminal emulator with Gruvbox theme";

  config = lib.mkIf cfg.enable {
    programs.ghostty = lib.mkIf hasGui {
      enable = true;
      package = pkgs.ghostty-bin;

      settings = {
        theme = "Gruvbox Dark";
        custom-shader = [
          "${config.home.homeDirectory}/.config/ghostty/shaders/cursor_gruvbox.glsl"
        ];
        auto-update = "off";
      };
    };

    xdg.configFile = lib.mkIf hasGui {
      "ghostty/shaders".source = ../config/ghostty/shaders;
    };
  };
}

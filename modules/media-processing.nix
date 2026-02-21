{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.media-processing;
  hasGui = config.profiles.hasGui;
in
{
  options.profiles.media-processing.enable = lib.mkEnableOption "Media processing tools (ffmpeg, imagemagick, mpv)";

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.ffmpeg-full
      pkgs.imagemagick
      pkgs.mediainfo
    ];

    programs.mpv = lib.mkIf hasGui {
      enable = true;
    };
  };
}

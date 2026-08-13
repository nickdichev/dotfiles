{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.onlyeq;
  hasGui = config.profiles.hasGui;
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  options.profiles.onlyeq.enable = lib.mkEnableOption "OnlyEQ system-wide equalizer";

  config = lib.mkIf (cfg.enable && hasGui && isDarwin) {
    home.packages = [
      (pkgs.callPackage ../pkgs/onlyeq { })
    ];
  };
}

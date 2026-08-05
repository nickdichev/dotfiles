{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.maintenance;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  pkgs-unstable = import inputs.nixpkgs-unstable { inherit (pkgs) system; };
  mole = pkgs-unstable.mole-cleaner;
in
{
  options.profiles.maintenance.enable = lib.mkEnableOption "Periodic workstation maintenance";

  config = lib.mkIf (cfg.enable && isDarwin) {
    home.packages = [ mole ];

    launchd.agents.mole-cleaner = {
      enable = true;
      config = {
        ProgramArguments = [
          (lib.getExe mole)
          "clean"
        ];
        StartInterval = 14 * 24 * 60 * 60;
        ProcessType = "Background";
        LowPriorityIO = true;
        Nice = 10;
        WorkingDirectory = config.home.homeDirectory;
        EnvironmentVariables.HOME = config.home.homeDirectory;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/mole-cleaner.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mole-cleaner.error.log";
      };
    };
  };
}

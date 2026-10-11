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
  portalRepo = "${config.home.homeDirectory}/Workspace/portal/cms";

  # Determinate Nixd's automatic GC is disabled on dev boxes, so this job owns
  # store GC (`clean all` includes `nix`). Both tools only act on what they can
  # prove is stale; databases are never part of `all`.
  portalMaintenance = pkgs.writeShellApplication {
    name = "portal-maintenance";
    text = ''
      repo=${lib.escapeShellArg portalRepo}
      if [ ! -d "$repo/.git" ]; then
        echo "no Portal checkout at $repo; skipping"
        exit 0
      fi
      cd "$repo"
      status=0

      echo "== $(date -u +%FT%TZ) portal-dev-reap --apply"
      portal-dev-reap --repo "$repo" --apply || status=$?

      echo "== $(date -u +%FT%TZ) portal-disk-maintenance clean all"
      nix run "$repo#portal-disk-maintenance" -- clean all || status=$?

      echo "== $(date -u +%FT%TZ) done (status $status)"
      exit "$status"
    '';
  };
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

    launchd.agents.portal-maintenance = {
      enable = true;
      config = {
        ProgramArguments = [ (lib.getExe portalMaintenance) ];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 30;
          }
        ];
        ProcessType = "Background";
        LowPriorityIO = true;
        Nice = 10;
        WorkingDirectory = config.home.homeDirectory;
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          # herdr, gh, and portal-dev-reap come from the user profile.
          PATH = lib.concatStringsSep ":" [
            "/etc/profiles/per-user/${config.home.username}/bin"
            "/run/current-system/sw/bin"
            "/nix/var/nix/profiles/default/bin"
            "/usr/bin"
            "/bin"
            "/usr/sbin"
            "/sbin"
          ];
        };
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/portal-maintenance.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/portal-maintenance.log";
      };
    };
  };
}

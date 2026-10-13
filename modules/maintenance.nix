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
  # prove is stale; databases are never part of `all`. It cannot delete the
  # root-owned system generations; the host configuration prunes those.
  #
  # launchd fires this hourly. It works every six hours, and on any tick where
  # the disk is under pressure, when it also drops the idle window to zero.
  pressureGib = 20;
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

      stamp="$HOME/Library/Caches/portal-maintenance.last-run"
      free=$(df -g "$HOME" | awk 'NR == 2 { print $4 }')
      days=1
      if [ "$free" -lt ${toString pressureGib} ]; then
        days=0
      elif [ -n "$(find "$stamp" -mmin -350 2>/dev/null)" ]; then
        exit 0
      fi
      echo "== $(date -u +%FT%TZ) free ''${free} GiB; idle window ''${days}d"

      echo "== $(date -u +%FT%TZ) portal-dev-reap --apply"
      portal-dev-reap --repo "$repo" --apply || status=$?

      echo "== $(date -u +%FT%TZ) portal-disk-maintenance clean all --days $days"
      nix run "$repo#portal-disk-maintenance" -- clean all --days "$days" || status=$?

      # An LLM advisor decides the worktrees the proofs above cannot; only its
      # high-confidence advice is applied, and removals keep the branch.
      echo "== $(date -u +%FT%TZ) portal-disk-maintenance review --auto"
      nix run "$repo#portal-disk-maintenance" -- review --auto || status=$?
      touch "$stamp"

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
        StartInterval = 60 * 60;
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

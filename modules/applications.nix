{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.applications;
  hasGui = config.profiles.hasGui;
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  isAarch64Darwin = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
  # Set to false to switch back to pkgs-unstable.raycast.
  useRaycastOverride = true;
  raycastPackage =
    if useRaycastOverride then
      pkgs-unstable.raycast.overrideAttrs (_: {
        version = "1.104.23";
        src = pkgs-unstable.fetchurl {
          name = "Raycast.dmg";
          url = "https://releases.raycast.com/releases/1.104.23/download?build=arm";
          hash = "sha256-/aotbycZmY8FSOLzUSmRMMfzwsN/2v08oNe4iteY2oE=";
        };
      })
    else
      pkgs-unstable.raycast;
  altTabPackage = pkgs.callPackage ../pkgs/alt-tab-macos-bin { };
  altTabBundleIdentifier = "com.lwouis.alt-tab-macos";
  githubPrTitleUserscript = pkgs.writeText "github-pr-title.user.js" ''
    // ==UserScript==
    // @name        GitHub PR number first in title
    // @match       https://github.com/*/*/pull/*
    // @run-at      document-start
    // ==/UserScript==

    (() => {
      const setTitle = () => {
        const match = location.pathname.match(/^\/[^/]+\/[^/]+\/pull\/(\d+)/);
        if (!match) return;

        const pr = match[1];
        const prefix = `#''${pr} \u00b7 `;

        if (document.title.startsWith(prefix)) return;

        const cleaned = document.title.replace(/^#\d+\s+[\u00b7-]\s+/, "");
        document.title = `''${prefix}''${cleaned}`;
      };

      setTitle();

      const observeTitle = () => {
        const target = document.head || document.documentElement;
        new MutationObserver(setTitle).observe(target, {
          childList: true,
          subtree: true,
          characterData: true,
        });
      };

      window.addEventListener("popstate", setTitle);
      document.addEventListener("turbo:load", setTitle);
      document.addEventListener("turbo:render", setTitle);
      observeTitle();

      let retries = 0;
      const retry = setInterval(() => {
        setTitle();
        retries += 1;
        if (retries >= 10) clearInterval(retry);
      }, 500);
    })();
  '';
  slackUpdatePolicyIdentifier = "com.nickdichev.slack-no-auto-updates";
  slackUpdatePolicyPath = "${config.xdg.configHome}/macos-profiles/slack-update-policy.mobileconfig";
  slackUpdatePolicyProfile = (pkgs.formats.plist { }).generate "slack-update-policy.mobileconfig" {
    PayloadContent = [
      {
        PayloadContent = {
          "com.tinyspeck.slackmacgap" = {
            Forced = [
              {
                mcx_preference_settings.AutoUpdate = false;
              }
            ];
          };
        };
        PayloadDisplayName = "Slack Update Policy";
        PayloadIdentifier = "${slackUpdatePolicyIdentifier}.managed-preferences";
        PayloadType = "com.apple.ManagedClient.preferences";
        PayloadUUID = "00641E7E-7A42-45BC-A505-008856550752";
        PayloadVersion = 1;
      }
    ];
    PayloadDescription = "Disables Slack's built-in updater so Slack can be managed by Nix without ShipIt helper prompts.";
    PayloadDisplayName = "Slack Update Policy";
    PayloadIdentifier = slackUpdatePolicyIdentifier;
    PayloadOrganization = "Nick Dichev";
    PayloadRemovalDisallowed = false;
    PayloadScope = "User";
    PayloadType = "Configuration";
    PayloadUUID = "D6395E18-5EE3-4F98-86A6-B3DD0FFC4775";
    PayloadVersion = 1;
  };
  installSlackUpdatePolicy = pkgs.writeShellApplication {
    name = "install-slack-update-policy";
    text = ''
      profile=${lib.escapeShellArg slackUpdatePolicyPath}
      identifier=${lib.escapeShellArg slackUpdatePolicyIdentifier}
      username=${lib.escapeShellArg config.profiles.username}

      if /usr/bin/profiles list -type configuration -user "$username" 2>/dev/null \
        | /usr/bin/grep -Fq "profileIdentifier: $identifier"; then
        echo "Slack Update Policy is already installed."
        exit 0
      fi

      if [[ ! -e "$profile" ]]; then
        echo "Profile not found at $profile. Apply the Home Manager configuration first." >&2
        exit 1
      fi

      /usr/bin/open "$profile"
      echo "System Settings will open. Review 'Slack Update Policy', then click Install."
    '';
  };
in
{
  options.profiles.applications.enable = lib.mkEnableOption "Desktop applications (obsidian, raycast, Hermes, tablepro, rustdesk)";

  config = lib.mkIf cfg.enable {
    home.activation.copyUserscripts = lib.mkIf (hasGui && isDarwin) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        userscripts_dir="$HOME/.config/userscripts"
        userscript_file="$userscripts_dir/github-pr-title.user.js"

        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$userscripts_dir"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$userscript_file"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${githubPrTitleUserscript} "$userscript_file"
      ''
    );
    home.activation.checkSlackUpdatePolicy = lib.mkIf (hasGui && isDarwin) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! /usr/bin/profiles list -type configuration -user ${lib.escapeShellArg config.profiles.username} \
          2>/dev/null | /usr/bin/grep -Fq \
          ${lib.escapeShellArg "profileIdentifier: ${slackUpdatePolicyIdentifier}"}; then
          echo "Slack Update Policy is not installed; run install-slack-update-policy once on this Mac."
        fi
      ''
    );
    xdg.configFile."macos-profiles/slack-update-policy.mobileconfig" = lib.mkIf (hasGui && isDarwin) {
      source = slackUpdatePolicyProfile;
    };
    xdg.configFile."raycast/script-commands/sleep-displays.sh" = lib.mkIf (hasGui && isDarwin) {
      source = ../config/raycast/script-commands/sleep-displays.sh;
    };
    home.activation.configureAltTab = lib.mkIf (hasGui && isDarwin) (
      lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
        # Home Manager owns AltTab startup and upgrades. Disable the app's
        # self-managed login item and updater so neither can mutate Nix state.
        $DRY_RUN_CMD /usr/bin/defaults write ${altTabBundleIdentifier} startAtLogin -bool false
        $DRY_RUN_CMD /usr/bin/defaults write ${altTabBundleIdentifier} updatePolicy -string "0"
        $DRY_RUN_CMD /usr/bin/defaults write ${altTabBundleIdentifier} SUEnableAutomaticChecks -bool false
        $DRY_RUN_CMD /usr/bin/defaults write ${altTabBundleIdentifier} SUAutomaticallyUpdate -bool false

        legacy_agent="$HOME/Library/LaunchAgents/${altTabBundleIdentifier}.plist"
        legacy_service="gui/$UID/${altTabBundleIdentifier}"

        if /bin/launchctl print "$legacy_service" >/dev/null 2>&1; then
          $DRY_RUN_CMD /bin/launchctl bootout "$legacy_service"
        fi
        $DRY_RUN_CMD /bin/rm -f "$legacy_agent"
      ''
    );
    launchd.agents.alt-tab = lib.mkIf (hasGui && isDarwin) {
      enable = true;
      config = {
        Program = "${altTabPackage}/Applications/AltTab.app/Contents/MacOS/AltTab";
        RunAtLoad = true;
        LimitLoadToSessionType = "Aqua";
        ProcessType = "Interactive";
        LegacyTimers = true;
        AssociatedBundleIdentifiers = altTabBundleIdentifier;
      };
    };
    home.packages = [
    ]
    ++ lib.optionals hasGui [
      pkgs-unstable.godot
      pkgs.obsidian
      pkgs.slack
      pkgs-unstable.telegram-desktop
    ]
    ++ lib.optionals (hasGui && isDarwin) [

      installSlackUpdatePolicy
      altTabPackage
      pkgs-unstable.blackhole
      pkgs-unstable.orbstack
      raycastPackage

      (pkgs.callPackage ../pkgs/rustdesk { })
      (pkgs.callPackage ../pkgs/redisinsight { })
      (pkgs.callPackage ../pkgs/handy { })
      (pkgs.callPackage ../pkgs/tablepro { })
      (pkgs.callPackage ../pkgs/orcaslicer { })

    ]
    ++ lib.optionals (hasGui && isAarch64Darwin) [
      (pkgs.callPackage ../pkgs/hermes-desktop { })
    ]
    ++ lib.optionals (hasGui && isLinux) [
      pkgs.redisinsight
    ];
  };
}

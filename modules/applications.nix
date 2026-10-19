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
  altTabPackage = pkgs.callPackage ../pkgs/alt-tab-macos-bin { };
  vicinaePackage = pkgs.callPackage ../pkgs/vicinae { };
  # Ids derive from the name so a link keeps its open count across switches;
  # the "hm-" prefix marks the entries this module owns in shortcuts.json.
  vicinaeQuicklinks = lib.mapAttrsToList (name: link: {
    id = "hm-${builtins.substring 0 12 (builtins.hashString "sha256" name)}";
    inherit name;
    inherit (link) url app;
    icon =
      if link.icon != null then
        link.icon
      else
        "icon://favicon/${hostOf link.url}?fallback=icon://builtin/link";
  }) (lib.filterAttrs (_: link: link.enable) cfg.vicinae.quicklinks);
  hostOf = url: builtins.head (builtins.match "[a-z]+://([^/:?#]+).*" url);
  vicinaeQuicklinksFile = pkgs.writeText "vicinae-quicklinks.json" (
    builtins.toJSON vicinaeQuicklinks
  );
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
  options.profiles.applications = {
    enable = lib.mkEnableOption "Desktop applications (obsidian, vicinae, Hermes, tablepro, rustdesk)";

    vicinae.quicklinks = lib.mkOption {
      description = ''
        Vicinae quicklinks keyed by display name. Consumers can add links per
        machine or set `enable = false` to drop a shared one. Links created in
        the Vicinae UI are left alone.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            url = lib.mkOption {
              type = lib.types.str;
              description = "Link to open; may use Vicinae's {argument} placeholders.";
            };
            icon = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Vicinae icon URI; defaults to the site's favicon.";
            };
            app = lib.mkOption {
              type = lib.types.str;
              default = "default";
              description = "Application that opens the link.";
            };
          };
        }
      );
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    profiles.applications.vicinae.quicklinks = import ../config/vicinae/quicklinks.nix;

    # Vicinae rewrites shortcuts.json whenever a link is opened or edited, so
    # it cannot be a store symlink. Merge the declared links into it instead,
    # carrying over usage stats, and restart Vicinae, which only reads the
    # file at startup and would otherwise write its stale copy back.
    home.activation.syncVicinaeQuicklinks = lib.mkIf (hasGui && isAarch64Darwin) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        shortcuts_file="${config.xdg.dataHome}/vicinae/shortcuts/shortcuts.json"
        current='[]'
        if [[ -s "$shortcuts_file" ]]; then
          current=$(${pkgs.coreutils}/bin/cat "$shortcuts_file")
        fi

        merged=$(${pkgs.jq}/bin/jq -c --slurpfile declared ${vicinaeQuicklinksFile} \
          --argjson now "$(${pkgs.coreutils}/bin/date +%s)" '
          $declared[0] as $declared
          | . as $current
          | ($declared | map(.id)) as $ids
          | ($declared | map(.name)) as $names
          | [ .[] | select((.id | startswith("hm-") | not) and ((.name | IN($names[])) | not)) ]
          + [ $declared[] as $d
              | ([ $current[] | select(.id == $d.id) ] + [ $current[] | select(.name == $d.name) ])[0] as $old
              | $d + {
                  openCount: ($old.openCount // 0),
                  createdAt: ($old.createdAt // $now),
                  updatedAt: (if $old != null and ($old | {name, url, icon, app}) == ($d | {name, url, icon, app})
                    then $old.updatedAt else $now end)
                }
              + (if $old.lastUsedAt != null then { lastUsedAt: $old.lastUsedAt } else {} end) ]
        ' <<<"$current")

        if [[ "$merged" != "$(${pkgs.jq}/bin/jq -c . <<<"$current")" ]]; then
          was_running=false
          if /usr/bin/pgrep -qx Vicinae; then
            was_running=true
            $DRY_RUN_CMD /usr/bin/pkill -x Vicinae
            for _ in $(${pkgs.coreutils}/bin/seq 50); do
              /usr/bin/pgrep -qx Vicinae || break
              ${pkgs.coreutils}/bin/sleep 0.1
            done
          fi

          $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$shortcuts_file")"
          if [[ -z "''${DRY_RUN:-}" ]]; then
            printf '%s\n' "$merged" >"$shortcuts_file"
          fi

          if $was_running; then
            $DRY_RUN_CMD /usr/bin/open -g ${vicinaePackage}/Applications/Vicinae.app
          fi
        fi
      ''
    );

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
    xdg.dataFile."vicinae/scripts/sleep-displays.sh" = lib.mkIf (hasGui && isAarch64Darwin) {
      source = ../config/vicinae/scripts/sleep-displays.sh;
    };
    xdg.dataFile."vicinae/scripts/toggle-appearance.sh" = lib.mkIf (hasGui && isAarch64Darwin) {
      source = ../config/vicinae/scripts/toggle-appearance.sh;
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

      (pkgs.callPackage ../pkgs/rustdesk { })
      (pkgs.callPackage ../pkgs/redisinsight { })
      (pkgs.callPackage ../pkgs/handy { })
      (pkgs.callPackage ../pkgs/tablepro { })
      (pkgs.callPackage ../pkgs/orcaslicer { })

    ]
    ++ lib.optionals (hasGui && isAarch64Darwin) [
      (pkgs.callPackage ../pkgs/hermes-desktop {
        hermes-agent = inputs.hermes-agent.packages.${pkgs.system}.default;
        hermes-desktop = inputs.hermes-agent.packages.${pkgs.system}.desktop;
        # Same electron upstream built the app and its native modules against.
        electron = inputs.hermes-agent.inputs.nixpkgs.legacyPackages.${pkgs.system}.electron;
        icon = "${inputs.hermes-agent}/apps/desktop/assets/icon.icns";
      })
      vicinaePackage
    ]
    ++ lib.optionals (hasGui && isLinux) [
      pkgs.redisinsight
    ];
  };
}

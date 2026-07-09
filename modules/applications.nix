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
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit (pkgs) system;
    config.allowUnfree = true;
  };
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
in
{
  options.profiles.applications.enable = lib.mkEnableOption "Desktop applications (obsidian, raycast, tablepro, rustdesk)";

  config = lib.mkIf cfg.enable {
    targets.darwin.defaults = lib.mkIf isDarwin {
      "com.tinyspeck.slackmacgap" = {
        AutoUpdate = false;
        SlackNoAutoUpdates = true;
      };
    };

    home.activation.copyUserscripts = lib.mkIf (hasGui && isDarwin) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        userscripts_dir="$HOME/.config/userscripts"
        userscript_file="$userscripts_dir/github-pr-title.user.js"

        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$userscripts_dir"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$userscript_file"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${githubPrTitleUserscript} "$userscript_file"
      ''
    );
    home.packages = [
    ]
    ++ lib.optionals hasGui [
      pkgs-unstable.godot
      pkgs.obsidian
      pkgs.slack
      pkgs-unstable.telegram-desktop
    ]
    ++ lib.optionals (hasGui && isDarwin) [

      pkgs-unstable.alt-tab-macos
      pkgs-unstable.blackhole
      pkgs-unstable.raycast

      (pkgs.callPackage ../pkgs/rustdesk { })
      (pkgs.callPackage ../pkgs/redisinsight { })
      (pkgs.callPackage ../pkgs/handy { })
      (pkgs.callPackage ../pkgs/tablepro { })
      (pkgs.callPackage ../pkgs/orcaslicer { })

    ]
    ++ lib.optionals (hasGui && isLinux) [
      pkgs.redisinsight
    ];
  };
}

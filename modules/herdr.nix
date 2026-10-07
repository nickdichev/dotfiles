{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.herdr;
  herdr = inputs.herdr.packages.${pkgs.system}.default;
  claudeIntegrationHook = {
    matcher = "^(startup|resume|clear|compact|fork)$";
    hooks = [
      {
        type = "command";
        command = "bash '${config.home.homeDirectory}/.claude/hooks/herdr-agent-state.sh' session";
        timeout = 10;
      }
    ];
  };
  terminalBrowserSupported = builtins.elem pkgs.system [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
  terminalBrowser = pkgs.callPackage ../pkgs/terminal-browser { };
  terminalBrowserPlugin = "${inputs.terminal-browser-src}/herdr-plugin";
in
{
  options.profiles.herdr = {
    enable = lib.mkEnableOption "Herdr terminal agent multiplexer";

    terminalBrowser.enable = lib.mkEnableOption "Terminal Browser with its Herdr plugin";
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.packages = [ herdr ];

        xdg.configFile."herdr/config.toml".source = ../config/herdr/config.toml;

        # Declare the Claude integration instead of running Herdr's installer:
        # its settings file is a Home Manager symlink into the Nix store, which
        # the installer refuses to touch once the store deduplicates it. The
        # integration is this hook entry plus the script it runs.
        programs.claude-code.settings.hooks.SessionStart = lib.mkIf config.profiles.ai.enable [
          claudeIntegrationHook
        ];

        home.file.".claude/hooks/herdr-agent-state.sh" = lib.mkIf config.profiles.ai.enable {
          source = "${inputs.herdr}/src/integration/assets/claude/herdr-agent-state.sh";
          executable = true;
          # Replace the copy an earlier installer run left behind.
          force = true;
        };

        # Codex keeps its hooks and config in files it rewrites itself, so
        # Herdr's installer still owns that side.
        home.activation.installHerdrAgentIntegrations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if ${lib.boolToString config.profiles.ai.enable}; then
            $DRY_RUN_CMD ${herdr}/bin/herdr integration install codex
          fi
        '';
      }

      (lib.mkIf cfg.terminalBrowser.enable {
        assertions = [
          {
            assertion = terminalBrowserSupported;
            message = "Terminal Browser does not publish a binary for ${pkgs.system}.";
          }
        ];

        home.packages = lib.optional terminalBrowserSupported terminalBrowser;

        home.activation.linkTerminalBrowserHerdrPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if ! $DRY_RUN_CMD ${herdr}/bin/herdr plugin link ${lib.escapeShellArg terminalBrowserPlugin}; then
            echo "Could not link the Terminal Browser plugin. Restart Herdr with version 0.9.0, then run Home Manager again." >&2
          fi
        '';

        home.file = lib.mkIf terminalBrowserSupported {
          ".agents/skills/terminal-browser" = {
            source = "${terminalBrowser}/skills/codex/terminal-browser";
            recursive = true;
          };

          ".claude/skills/terminal-browser" = {
            source = "${terminalBrowser}/skills/default/terminal-browser";
            recursive = true;
          };
        };
      })
    ]
  );
}

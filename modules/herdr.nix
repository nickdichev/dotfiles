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
    matcher = "*";
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

        # Herdr owns the generated scripts and Codex hook entry. Declare the
        # Claude entry so its Home Manager-managed settings file stays a symlink
        # when the integration installer verifies it.
        programs.claude-code.settings.hooks.SessionStart = lib.mkIf config.profiles.ai.enable [
          claudeIntegrationHook
        ];

        home.activation.installHerdrAgentIntegrations = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if ${lib.boolToString config.profiles.ai.enable}; then
            $DRY_RUN_CMD ${herdr}/bin/herdr integration install codex
            $DRY_RUN_CMD ${herdr}/bin/herdr integration install claude
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
            echo "Could not link the Terminal Browser plugin. Restart Herdr with version 0.8.2, then run Home Manager again." >&2
          fi
        '';

        home.file = lib.mkIf terminalBrowserSupported {
          ".codex/skills/terminal-browser" = {
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

{ inputs }:
{
  config,
  clanVars ? null,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.ai;
  kagiApiKeyFile =
    if clanVars != null && clanVars ? generators && clanVars.generators ? "kagi-api-key" then
      clanVars.generators."kagi-api-key".files.api_key.path
    else
      null;

  llm-agents = inputs.llm-agents.packages.${pkgs.system};
  codex = llm-agents.codex;
  claude-code = llm-agents.claude-code;
  playwright-cli = inputs.portal-nix-overlay.packages.${pkgs.system}.playwright-cli;

  # Re-wrap pi so `pi install` works: needs npm on PATH (it shells out to
  # `npm root -g`) and a writable per-user npm prefix instead of the store.
  pi = pkgs.symlinkJoin {
    name = "pi-${llm-agents.pi.version or "wrapped"}";
    paths = [ llm-agents.pi ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/pi \
        --suffix PATH : ${lib.makeBinPath [ pkgs.nodejs ]} \
        --run 'export NPM_CONFIG_PREFIX="''${NPM_CONFIG_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/pi/npm}"'
    '';
  };

  kagiWrapper =
    if kagiApiKeyFile != null then
      pkgs.writeShellScript "kagi-mcp-wrapper" ''
        export KAGI_API_KEY="$(cat ${kagiApiKeyFile})"
        exec ${pkgs.uv}/bin/uvx "$@"
      ''
    else
      null;

  mcpServers = {
    nixos = {
      args = [
        "--from"
        "git+https://github.com/nickdichev/mcp-nixos@Add-clan-options"
        "mcp-nixos"
      ];
      command = "${pkgs.uv}/bin/uvx";
    };
  }
  // lib.optionalAttrs (kagiWrapper != null) {
    kagi = {
      args = [ "kagimcp" ];
      command = "${kagiWrapper}";
    };
  };
in
{
  options.profiles.ai = {
    enable = lib.mkEnableOption "AI tools (claude-code, codex, MCP servers)";
  };

  config = lib.mkIf cfg.enable {
    programs.codex = {
      enable = true;
      package = codex;
      settings = null;
      profiles.home-manager.mcp_servers = mcpServers;
    };

    programs.claude-code = {
      enable = true;

      package = claude-code;

      commandsDir = ../config/claude/commands;

      skills = {
        creating-skills = ../config/claude/skills/creating-skills;
        playwright-cli = ../config/claude/skills/playwright-cli;
      };

      settings = {
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = 1;

        skipDangerousModePermissionPrompt = true;

        effortLevel = "high";

        attribution = {
          commit = "";
          pr = "";
        };

        statusLine = {
          type = "command";
          command = "~/.claude/statusline.sh";
          padding = 1;
        };
      };

      mcpServers = mcpServers;
    };

    home.packages = [
      pi
      playwright-cli
    ];

    home.file = {
      ".codex/skills/audit-nix-app-updates" = {
        source = ../config/codex/skills/audit-nix-app-updates;
        recursive = true;
      };

      ".claude/statusline.sh" = {
        source = ../config/claude/statusline.sh;
        executable = true;
      };
    };
  };
}

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
  codex-profiles = inputs.codex-profiles.packages.${pkgs.system}.default;
  claude-code = llm-agents.claude-code;
  playwright-cli = inputs.portal-nix-overlay.packages.${pkgs.system}.playwright-cli;
  herdr = inputs.herdr.packages.${pkgs.system}.default;

  # Generate the skill from the packaged CLI so its instructions always match
  # the Herdr version pinned by flake.lock.
  herdrSkill = pkgs.runCommand "herdr-agent-skill" { } ''
    mkdir -p "$out"
    ${herdr}/bin/herdr --skill > "$out/SKILL.md"
  '';

  mcpServers = import ../lib/mcp-servers.nix {
    inherit kagiApiKeyFile pkgs;
  };

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
    };

    programs.claude-code = {
      enable = true;

      package = claude-code;

      commandsDir = ../config/claude/commands;

      skills = {
        creating-skills = ../config/claude/skills/creating-skills;
        herdr = herdrSkill;
        playwright-cli = ../config/claude/skills/playwright-cli;
        watch-ci = ../config/skills/watch-ci;
        working-with-nixbot = ../config/skills/working-with-nixbot;
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
      codex-profiles
      pi
      playwright-cli
    ];

    # Match codex-profiles' opt-in terminal integration.  `shell-init` supplies
    # the `use` shell wrapper, an active-profile prompt prefix, and profile-aware
    # completions; the two environment variables add per-run terminal feedback.
    programs.zsh.initContent = lib.mkOrder 2000 ''
      eval "$(${codex-profiles}/bin/codex-profile shell-init zsh --prompt --completions)"
      export CODEX_PROFILE_TERMINAL_TITLE=1
      export CODEX_PROFILE_NOTIFY=1
    '';

    # Keep the existing shortcut, but let its profile be selected by the
    # nearest workspace binding and checked by codex-profiles' guard.
    programs.zsh.shellAliases.cdx = lib.mkForce "codex-profile run -- --yolo";

    home.file = {
      # ~/.agents/skills is shared by every CODEX_HOME selected by
      # codex-profiles; ~/.codex/skills would apply only to the default home.
      ".agents/skills/audit-nix-app-updates" = {
        source = ../config/codex/skills/audit-nix-app-updates;
        recursive = true;
      };

      ".agents/skills/watch-ci" = {
        source = ../config/skills/watch-ci;
        recursive = true;
      };

      ".agents/skills/herdr" = {
        source = herdrSkill;
        recursive = true;
      };

      ".agents/skills/working-with-nixbot" = {
        source = ../config/skills/working-with-nixbot;
        recursive = true;
      };

      ".claude/statusline.sh" = {
        source = ../config/claude/statusline.sh;
        executable = true;
      };
    };
  };
}

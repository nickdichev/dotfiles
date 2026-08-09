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

  codexMcpConfig = (pkgs.formats.toml { }).generate "codex-mcp.toml" {
    mcp_servers = mcpServers;
  };

  # Keep Codex's main config writable so it can persist runtime state such as
  # project and hook trust. Home Manager owns only the marked MCP section.
  codexConfigSetup = ''
    config_dir="''${CODEX_HOME:-$HOME/.codex}"
    config_file="$config_dir/config.toml"
    mkdir -p "$config_dir"

    if [ -L "$config_file" ]; then
      tmp_file="$(${pkgs.coreutils}/bin/mktemp "$config_file.tmp.XXXXXX")"
      ${pkgs.coreutils}/bin/cp -L "$config_file" "$tmp_file"
      ${pkgs.coreutils}/bin/rm "$config_file"
      ${pkgs.coreutils}/bin/mv "$tmp_file" "$config_file"
    elif [ ! -e "$config_file" ]; then
      ${pkgs.coreutils}/bin/touch "$config_file"
    fi

    stripped_file="$(${pkgs.coreutils}/bin/mktemp "$config_file.stripped.XXXXXX")"
    tmp_file="$(${pkgs.coreutils}/bin/mktemp "$config_file.tmp.XXXXXX")"

    ${pkgs.gawk}/bin/awk '
      $0 == "# BEGIN home-manager managed mcp_servers" { skip = 1; next }
      $0 == "# END home-manager managed mcp_servers" { skip = 0; next }
      !skip { print }
    ' "$config_file" > "$stripped_file"

    {
      ${pkgs.coreutils}/bin/cat "$stripped_file"
      printf '\n# BEGIN home-manager managed mcp_servers\n'
      ${pkgs.coreutils}/bin/cat ${codexMcpConfig}
      printf '# END home-manager managed mcp_servers\n'
    } > "$tmp_file"

    ${pkgs.coreutils}/bin/mv "$tmp_file" "$config_file"
    ${pkgs.coreutils}/bin/rm -f "$stripped_file"
    ${pkgs.coreutils}/bin/chmod 600 "$config_file"
  '';
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
      pi
      playwright-cli
    ];

    home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] codexConfigSetup;

    home.file = {
      ".codex/skills/audit-nix-app-updates" = {
        source = ../config/codex/skills/audit-nix-app-updates;
        recursive = true;
      };

      ".codex/skills/watch-ci" = {
        source = ../config/skills/watch-ci;
        recursive = true;
      };

      ".codex/skills/working-with-nixbot" = {
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

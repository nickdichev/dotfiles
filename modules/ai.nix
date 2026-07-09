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
  codexInitialConfig = pkgs.writeText "codex-config.toml" ''
    [features]
    goals = true
  '';

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

  codexConfigSetup = ''
    config_dir="''${CODEX_HOME:-$HOME/.codex}"
    config_file="$config_dir/config.toml"
    mkdir -p "$config_dir"

    if [ -L "$config_file" ]; then
      tmp_file="$(${pkgs.coreutils}/bin/mktemp "$config_file.tmp.XXXXXX")"
      ${pkgs.coreutils}/bin/cp -L "$config_file" "$tmp_file"
      ${pkgs.coreutils}/bin/rm "$config_file"
      ${pkgs.coreutils}/bin/mv "$tmp_file" "$config_file"
      ${pkgs.coreutils}/bin/chmod u+rw "$config_file"
    elif [ ! -e "$config_file" ]; then
      if [ -e "$config_file.bak" ]; then
        ${pkgs.coreutils}/bin/cp "$config_file.bak" "$config_file"
      else
        ${pkgs.coreutils}/bin/cp ${codexInitialConfig} "$config_file"
      fi
      ${pkgs.coreutils}/bin/chmod u+rw "$config_file"
    fi

    update_managed_mcp_config() {
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
      ${pkgs.coreutils}/bin/chmod u+rw "$config_file"
    }

    update_managed_mcp_config
  '';

  codexWrapper = pkgs.writeShellScriptBin "codex" (
    ''
      set -eu

    ''
    + codexConfigSetup
    + ''

      ensure_project_trust() {
        project_path="$1"
        escaped_path="$(printf '%s' "$project_path" | ${pkgs.gnused}/bin/sed 's/\\/\\\\/g; s/"/\\"/g')"
        header="[projects.\"$escaped_path\"]"

        if ! ${pkgs.gnugrep}/bin/grep -Fqx "$header" "$config_file"; then
          {
            printf '\n%s\n' "$header"
            printf 'trust_level = "trusted"\n'
          } >> "$config_file"
        fi
      }
    ''
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (path: trust_level: ''
        if [ ${lib.escapeShellArg trust_level} = "trusted" ]; then
          ensure_project_trust ${lib.escapeShellArg path}
        fi
      '') cfg.codex.projectTrust
    )
    + ''

      git_root="$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -n "$git_root" ]; then
        git_root="$(${pkgs.coreutils}/bin/realpath "$git_root" 2>/dev/null || printf '%s\n' "$git_root")"

    ''
    + lib.concatMapStringsSep "\n" (trustedRoot: ''
      trusted_root="$(${pkgs.coreutils}/bin/realpath ${lib.escapeShellArg trustedRoot} 2>/dev/null || printf '%s\n' ${lib.escapeShellArg trustedRoot})"
      case "$git_root" in
        "$trusted_root"|"$trusted_root"/*)
          ensure_project_trust "$git_root"
          ;;
      esac
    '') cfg.codex.autoTrustGitRoots
    + ''
      fi

      exec ${codex}/bin/codex "$@"
    ''
  );
in
{
  options.profiles.ai = {
    enable = lib.mkEnableOption "AI tools (claude-code, codex, MCP servers)";

    codex.projectTrust = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.enum [
          "trusted"
          "untrusted"
        ]
      );
      default = { };
      example = {
        "/Users/nick/Workspace/personal/home" = "trusted";
      };
      description = "Codex project trust entries written to programs.codex.settings.projects.";
    };

    codex.autoTrustGitRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/Users/nick/Workspace/personal" ];
      description = ''
        Parent directories whose git repositories and worktrees should be marked
        trusted in Codex's writable config.toml when codex starts inside them.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.codex = {
      enable = true;
      package = codexWrapper;
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

    home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] codexConfigSetup;

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

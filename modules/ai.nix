{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.ai;
  # kagiApiKeyFile = clanVars.generators.kagi-api-key.files.api_key.path;
  kagiApiKeyFile = pkgs.writeText "kagi_api_key" "foobar";

  serena = inputs.serena.packages.${pkgs.system}.default;
  lightpanda = pkgs.callPackage ../pkgs/lightpanda { };
  gomcp = pkgs.callPackage ../pkgs/gomcp { };

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

  # Wrapper that ensures lightpanda is symlinked where gomcp expects it.
  # Go's os.UserConfigDir() returns ~/Library/Application Support on macOS
  # and $XDG_CONFIG_HOME (or ~/.config) on Linux.
  gomcpWrapper = pkgs.writeShellScript "gomcp-wrapper" ''
    if [ "$(uname)" = "Darwin" ]; then
      config_dir="$HOME/Library/Application Support/lightpanda-gomcp"
    else
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/lightpanda-gomcp"
    fi
    mkdir -p "$config_dir"
    ln -sf ${lightpanda}/bin/lightpanda "$config_dir/lightpanda"
    exec ${gomcp}/bin/gomcp "$@"
  '';

  # Wrapper script that reads the API key from file and runs uvx
  kagiWrapper = pkgs.writeShellScript "kagi-mcp-wrapper" ''
    export KAGI_API_KEY="$(cat ${kagiApiKeyFile})"
    exec ${pkgs.uv}/bin/uvx "$@"
  '';

  codexWrapper = pkgs.writeShellScriptBin "codex" (
    ''
      set -eu

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

      skillsDir = ../config/claude/skills;

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

      mcpServers = {
        # kagi = {
        #   args = [ "kagimcp" ];
        #   command = "${kagiWrapper}";
        # };

        nixos = {
          args = [
            "--from"
            "git+https://github.com/nickdichev/mcp-nixos@Add-clan-options"
            "mcp-nixos"
          ];
          command = "${pkgs.uv}/bin/uvx";
        };

        gomcp = {
          args = [ "stdio" ];
          command = "${gomcpWrapper}";
        };

        serena = {
          args = [
            "start-mcp-server"
            "--context=claude-code"
            "--project-from-cwd"
          ];
          command = "${serena}/bin/serena";
        };
      };
    };

    home.packages = [
      lightpanda
      pi
      playwright-cli
    ];

    home.activation.codexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
    '';

    # Copy serena config as a regular file (not a symlink) so Serena can
    # migrate it in-place when new fields are added across versions.
    home.activation.serenaConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -f "$HOME/.serena/serena_config.yml" ] || [ -L "$HOME/.serena/serena_config.yml" ]; then
        install -Dm644 ${pkgs.writeText "serena_config.yml" ''
          web_dashboard_open_on_launch: false
          projects: []
        ''} $HOME/.serena/serena_config.yml
      fi
    '';

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

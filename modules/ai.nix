{ inputs }:
{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.ai;
  # kagiApiKeyFile = clanVars.generators.kagi-api-key.files.api_key.path;
  kagiApiKeyFile = pkgs.writeText "kagi_api_key" "foobar";

  serena = inputs.serena.packages.${pkgs.system}.default;
  lightpanda = pkgs.callPackage ../pkgs/lightpanda { };
  gomcp = pkgs.callPackage ../pkgs/gomcp { };

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
in
{
  options.profiles.ai.enable = lib.mkEnableOption "AI tools (claude-code, codex, MCP servers)";

  config = lib.mkIf cfg.enable {
    programs.codex = {
      enable = true;

      package = inputs.llm-agents.packages.${pkgs.system}.codex;
    };

    programs.claude-code = {
      enable = true;

      package = inputs.llm-agents.packages.${pkgs.system}.claude-code;

      commandsDir = ../config/claude/commands;

      skillsDir = ../config/claude/skills;

      settings = {
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = 1;
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
            "git+https://github.com/nickdichev/mcp-nixos"
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

    home.packages = [ lightpanda ];

    home.file = {
      # https://github.com/oraios/serena/blob/main/src/serena/resources/serena_config.template.yml
      ".serena/serena_config.yml".source = pkgs.writeText "serena_config.yml" ''
        web_dashboard_open_on_launch: false
        projects: []
      '';
      ".claude/statusline.sh" = {
        source = ../config/claude/statusline.sh;
        executable = true;
      };
    };
  };
}

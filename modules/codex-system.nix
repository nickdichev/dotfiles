{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.codexSystem;
  tomlFormat = pkgs.formats.toml { };
  mcpServers = import ../lib/mcp-servers.nix {
    inherit pkgs;
    inherit (cfg) kagiApiKeyFile;
  };
in
{
  options.profiles.codexSystem = {
    enable = lib.mkEnableOption "system-wide Codex MCP configuration";

    kagiApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to the Kagi API key. The generated system config contains only a
        wrapper command path; the secret itself is never written to /etc.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."codex/config.toml".source = tomlFormat.generate "codex-system-config.toml" {
      mcp_servers = mcpServers;
    };
  };
}

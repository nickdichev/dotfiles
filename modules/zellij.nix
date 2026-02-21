{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.zellij;
  layoutsDir = ../config/zellij/layouts;
  layoutFiles = lib.filterAttrs (name: _: lib.hasSuffix ".kdl" name) (builtins.readDir layoutsDir);
  layoutEntries = lib.mapAttrs' (
    name: _:
    lib.nameValuePair "zellij/layouts/${name}" { source = "${layoutsDir}/${name}"; }
  ) layoutFiles;
in
{
  options.profiles.zellij = {
    enable = lib.mkEnableOption "Zellij terminal multiplexer";

    certDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.certs";
      description = "Directory containing TLS certificates for Zellij";
    };

    certName = lib.mkOption {
      type = lib.types.str;
      default = "buckwheat+2";
      description = "Certificate name used in Zellij configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zellij = {
      enable = true;
      enableZshIntegration = false; # Custom logic in shell.nix handles SSH nesting
    };

    xdg.configFile = {
      "zellij/config.kdl".source = pkgs.replaceVars ../config/zellij/config.kdl {
        certDir = cfg.certDir;
        certName = cfg.certName;
      };
    } // layoutEntries;
  };
}

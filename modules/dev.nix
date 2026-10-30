{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.dev;
  pkgs-unstable = import inputs.nixpkgs-unstable { inherit (pkgs) system; };
in
{
  options.profiles.dev.enable = lib.mkEnableOption "Development tools (direnv, gh, just)";

  config = lib.mkIf cfg.enable {

    home.packages = [
      pkgs.arduino-cli
      pkgs.just
      pkgs-unstable.niks3
      inputs.devenv.packages.${pkgs.system}.devenv
    ];

    # Supply libpq's default trust store for verified PostgreSQL connections.
    home.file.".postgresql/root.crt".source = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;

      config = {
        global = {
          hide_env_diff = true;
        };
      };
    };

    programs.gh = {
      enable = true;
    };

  };
}

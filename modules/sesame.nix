{
  config,
  dotfilesPackages ? { },
  lib,
  ...
}:
let
  cfg = config.profiles.sesame;
  package = dotfilesPackages.sesame or null;
in
{
  options.profiles.sesame.enable = lib.mkEnableOption "Clan client tools (sesame)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = package != null;
        message = ''
          profiles.sesame requires dotfilesPackages.sesame to be supplied by the consuming Home Manager configuration
        '';
      }
    ];

    home.packages = lib.optional (package != null) package;

    programs.zsh.shellAliases = {
      ses = "sesame";
    };
  };
}

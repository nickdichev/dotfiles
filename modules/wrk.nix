{
  config,
  dotfilesPackages ? { },
  lib,
  ...
}:
let
  cfg = config.profiles.wrk;
  package = dotfilesPackages.wrk or null;
in
{
  options.profiles.wrk.enable = lib.mkEnableOption "Workspace project switcher (wrk)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = package != null;
        message = ''
          profiles.wrk requires dotfilesPackages.wrk to be supplied by the consuming Home Manager configuration
        '';
      }
    ];

    home.packages = lib.optional (package != null) package;

    programs.zsh.initContent = lib.mkOrder 1500 ''
      wrk() {
        local dir
        dir="$(command wrk "$@")"
        if [[ $? -eq 0 && -n "$dir" ]]; then
          cd "$dir"
        fi
      }
    '';
  };
}

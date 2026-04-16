{ inputs }:
{ config, lib, pkgs, ... }:
let
  cfg = config.profiles.wrk;
  wrk = inputs.wrk.packages.${pkgs.system}.default;
in
{
  options.profiles.wrk.enable = lib.mkEnableOption "Workspace project switcher (wrk)";

  config = lib.mkIf cfg.enable {
    home.packages = [
      wrk
    ];

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

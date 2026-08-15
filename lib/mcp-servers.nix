{
  kagiApiKeyFile ? null,
  pkgs,
}:
let
  kagiWrapper =
    if kagiApiKeyFile != null then
      pkgs.writeShellScript "kagi-mcp-wrapper" ''
        export KAGI_API_KEY="$(cat ${kagiApiKeyFile})"
        exec ${pkgs.uv}/bin/uvx "$@"
      ''
    else
      null;
in
{
  nixos = {
    args = [
      "--from"
      "git+https://github.com/nickdichev/mcp-nixos@Add-clan-options"
      "mcp-nixos"
    ];
    command = "${pkgs.uv}/bin/uvx";
  };
}
// pkgs.lib.optionalAttrs (kagiWrapper != null) {
  kagi = {
    args = [ "kagimcp" ];
    command = "${kagiWrapper}";
  };
}

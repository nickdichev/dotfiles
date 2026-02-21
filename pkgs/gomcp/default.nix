{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "1.0.4";

  sources = {
    x86_64-linux = {
      url = "https://github.com/lightpanda-io/gomcp/releases/download/${version}/gomcp-linux-amd64";
      hash = "sha256:01s3ghm50b0qf1lhbmhrd1b10g5ai3l8c2x3m57c0pc9hs3l9hh3";
    };
    aarch64-linux = {
      url = "https://github.com/lightpanda-io/gomcp/releases/download/${version}/gomcp-linux-arm64";
      hash = "sha256:1bpk0i35sbi4fz8zpgxss14d92zfpgnx6ybhi6298sgymm6apnpa";
    };
    x86_64-darwin = {
      url = "https://github.com/lightpanda-io/gomcp/releases/download/${version}/gomcp-darwin-amd64";
      hash = "sha256:0bq5j5sywzqm51q3sxr78pxff6h19d28rbvx725c6gmsirxr3b3x";
    };
    aarch64-darwin = {
      url = "https://github.com/lightpanda-io/gomcp/releases/download/${version}/gomcp-darwin-arm64";
      hash = "sha256:0wjs8pgakdn5w1ihxss68nijpkajj7gc9qnc304i7gfy6djqzk91";
    };
  };

  src = fetchurl sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "gomcp";
  inherit version;
  inherit src;

  dontUnpack = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/gomcp
    runHook postInstall
  '';

  meta = {
    description = "MCP server for interacting with Lightpanda Browser via CDP";
    homepage = "https://github.com/lightpanda-io/gomcp";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames sources;
    mainProgram = "gomcp";
  };
}

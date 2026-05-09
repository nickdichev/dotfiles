{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.10.0";

  sources = {
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha256-cdiwcZPevnbhlpsHzPeRVsb5WQdunaNlTCKh+XwarUU=";
    };
    x86_64-darwin = {
      suffix = "darwin-x64";
      hash = "sha256-70O4DI3+7ZuZstem8QeiL/qrj9M65nYVflqzqUlpnSY=";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha256-epaG0urTx3nqr2mIClkDLzrxf+gOZE4EDyC0YyEPq8M=";
    };
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha256-ND3Kb1u0B5O+joNCvE4LzJjYpSFnt5QWDFGmuAmYns8=";
    };
  };

  source = sources.${stdenv.hostPlatform.system};

  src = fetchurl {
    url = "https://github.com/modem-dev/hunk/releases/download/v${version}/hunkdiff-${source.suffix}.tar.gz";
    inherit (source) hash;
  };
in
stdenv.mkDerivation {
  pname = "hunk";
  inherit version;
  inherit src;

  sourceRoot = "hunkdiff-${source.suffix}";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 hunk $out/bin/hunk
    runHook postInstall
  '';

  meta = {
    description = "Review-first terminal diff viewer for agentic coders";
    homepage = "https://github.com/modem-dev/hunk";
    license = lib.licenses.mit;
    platforms = builtins.attrNames sources;
    mainProgram = "hunk";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

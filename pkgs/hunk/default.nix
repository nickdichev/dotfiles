{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.15.1";

  sources = {
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha256-CjzN4yiW+gzjfh1k5JBKKXnL6yepoe+rxSRPAD8+p5g=";
    };
    x86_64-darwin = {
      suffix = "darwin-x64";
      hash = "sha256-Ow2kQl641Ahztn3RINefNmHgFPOnraWRTOi3CjEf2L4=";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha256-HM0so9T77rA364Bzoau1/SxuDiPtPNHc//w3Cdle26I=";
    };
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha256-HWWXh1d8j2JPyVWv2ULRAkrH+wNTL7+InS8mAkr5a/k=";
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

{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.23.0";

  sources = {
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha256-rkLP5SeYpPUdJfY864aFyipsswOaEk1qb8FyoRL41rg=";
    };
    x86_64-darwin = {
      suffix = "darwin-x64";
      hash = "sha256-FMUwJct7s6/WJztlgXq3oQArH46Usk46BU6VJk4WgOA=";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha256-W4korh6YeysXddH+Yu66vMCLn8mUAVTgzvJ9JJQct+Q=";
    };
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha256-eatkBsuyuADnPG+8JUavuX7U+8O1Cq0HLrmtEhUVgeY=";
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

{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:

let
  version = "1.2.7";
in
stdenv.mkDerivation {
  pname = "onlyeq";
  inherit version;

  src = fetchurl {
    url = "https://github.com/zollans/OnlyEQ/releases/download/v${version}/OnlyEQ.app.zip";
    hash = "sha256-yrjlR3duvACLV6KL+1G88WthabuoDB2kdyuh1MMuTRE=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ unzip ];

  dontStrip = true;
  dontPatchShebangs = true;
  # Preserve the upstream app and nested Sparkle signatures byte-for-byte.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R OnlyEQ.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "System-wide parametric equalizer for macOS";
    homepage = "https://github.com/zollans/OnlyEQ";
    changelog = "https://github.com/zollans/OnlyEQ/blob/v${version}/release-notes/${version}.md";
    license = lib.licenses.unlicense;
    platforms = lib.platforms.darwin;
    mainProgram = "OnlyEQ";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

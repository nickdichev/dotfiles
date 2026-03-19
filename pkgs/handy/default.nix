{
  lib,
  stdenv,
  fetchurl,
  undmg,
}:

let
  version = "0.7.11";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_aarch64.dmg";
      hash = "sha256-f5KcPyiL1ZkDRDXNRz2DsDr2Th7X5Ucz6iJYAbvXTow=";
    };
    x86_64-darwin = {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_x64.dmg";
      hash = "sha256-Hnxo5vPSlIOktlRUBFMKJeJrV/+T5GmzlVOFxmds/aY=";
    };
  };

  src = fetchurl sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "handy";
  inherit version;
  inherit src;

  sourceRoot = ".";

  nativeBuildInputs = [ undmg ];

  dontStrip = true;
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r Handy.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "A computer for your hand";
    homepage = "https://handy.computer";
    license = lib.licenses.unfree;
    platforms = builtins.attrNames sources;
    mainProgram = "Handy";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

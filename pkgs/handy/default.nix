{
  lib,
  stdenv,
  fetchurl,
  undmg,
}:

let
  version = "0.7.9";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_aarch64.dmg";
      hash = "sha256-ZvSHCW7CJe9uLCeapl/33+yG/T7ICHc3ljRUaEXTUKE=";
    };
    x86_64-darwin = {
      url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_x64.dmg";
      hash = "sha256-xzDRnaIrQJPmsTMDyq+/2V9zP/IQJu5ohOza68U2V3c=";
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

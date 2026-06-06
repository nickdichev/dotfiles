{
  lib,
  stdenv,
  fetchurl,
  _7zz,
}:

let
  version = "2.3.2";
in
stdenv.mkDerivation {
  pname = "orcaslicer";
  inherit version;

  src = fetchurl {
    url = "https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v${version}/OrcaSlicer_Mac_universal_V${version}.dmg";
    hash = "sha256-M09yZbHfkw6UrHWjGABbvmP2cP5xmp53eMMPTXyIfMI=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [ _7zz ];

  dontStrip = true;
  dontPatchShebangs = true;

  unpackPhase = ''
    7zz x -y -x'!Applications' $src 'OrcaSlicer.app'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R OrcaSlicer.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "G-code generator for 3D printers";
    homepage = "https://github.com/OrcaSlicer/OrcaSlicer";
    license = lib.licenses.agpl3Only;
    platforms = lib.platforms.darwin;
    mainProgram = "OrcaSlicer";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

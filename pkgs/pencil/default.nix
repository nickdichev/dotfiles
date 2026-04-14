{
  lib,
  stdenv,
  fetchurl,
  _7zz,
}:

let
  version = "1.1.48";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/highagency/pencil-desktop-releases/releases/download/v${version}/Pencil-${version}-mac-arm64.dmg";
      hash = "sha256-V/XsSPsr5JcE5vvmoCc0KKOeKdLUy/WQ+N99aWL5HaY=";
    };
    x86_64-darwin = {
      url = "https://github.com/highagency/pencil-desktop-releases/releases/download/v${version}/Pencil-${version}-mac-x64.dmg";
      hash = "sha256-JbyhcxWDnDWjQTpw+1Ad4LTm0uRSLuCrDFhi3MEQ9lk=";
    };
  };

  src = fetchurl sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "pencil";
  inherit version;
  inherit src;

  sourceRoot = ".";

  nativeBuildInputs = [ _7zz ];

  dontStrip = true;
  dontPatchShebangs = true;

  unpackPhase = ''
    7zz x -x'!Applications' -x'!.background' -x'!.DS_Store' -x'!.VolumeIcon.icns' -x'!.fseventsd' $src
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r Pencil.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Desktop app for Pencil";
    homepage = "https://www.pencil.dev";
    license = lib.licenses.unfree;
    platforms = builtins.attrNames sources;
    mainProgram = "Pencil";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

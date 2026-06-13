{
  lib,
  stdenv,
  fetchurl,
  _7zz,
}:

let
  version = "1.1.63";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/highagency/pencil-desktop-releases/releases/download/v${version}/Pencil-${version}-mac-arm64.dmg";
      hash = "sha256-VppyV3l8Pc4dpWxv3m9+JYnvjAwhx2NCrBZkGgQPig0=";
    };
    x86_64-darwin = {
      url = "https://github.com/highagency/pencil-desktop-releases/releases/download/v${version}/Pencil-${version}-mac-x64.dmg";
      hash = "sha256-qcUA64CDsQdRHBACZuimUT0j72p+XAlcSuN0QNM5H6o=";
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
    cp -r */Pencil.app $out/Applications/
    /usr/bin/codesign --force --deep --sign - "$out/Applications/Pencil.app"
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

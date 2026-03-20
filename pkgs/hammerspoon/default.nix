{
  lib,
  stdenv,
  fetchzip,
}:

let
  version = "1.1.1";
in
stdenv.mkDerivation {
  pname = "hammerspoon";
  inherit version;

  src = fetchzip {
    url = "https://github.com/Hammerspoon/hammerspoon/releases/download/${version}/Hammerspoon-${version}.zip";
    hash = "sha256-H+SlUyUO8Lzu0CjpwWDNCGF54yxHCszGYJ3DRZePMiA=";
  };

  dontStrip = true;
  dontPatchShebangs = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications/Hammerspoon.app
    cp -R . $out/Applications/Hammerspoon.app/
    runHook postInstall
  '';

  meta = {
    description = "Staggeringly powerful macOS desktop automation with Lua";
    homepage = "https://www.hammerspoon.org";
    license = lib.licenses.mit;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "Hammerspoon";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

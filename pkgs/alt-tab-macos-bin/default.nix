{
  fetchurl,
  lib,
  stdenvNoCC,
  unzip,
}:

let
  version = "11.10.1";
in
stdenvNoCC.mkDerivation {
  pname = "alt-tab-macos-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/lwouis/alt-tab-macos/releases/download/v${version}/AltTab-${version}.zip";
    hash = "sha256-qjUxl1N8z9N43Up/9DAwVhznxiJn3Qsxs4VpGw5/WUw=";
  };

  nativeBuildInputs = [ unzip ];

  dontUnpack = true;
  # Preserve upstream's Developer ID signature and designated requirement so
  # macOS TCC permissions survive package upgrades.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    unzip -q "$src" -d "$out/Applications"

    runHook postInstall
  '';

  meta = {
    description = "Windows-like alt-tab on macOS, using the upstream signed application bundle";
    homepage = "https://alt-tab.app";
    license = with lib.licenses; [
      gpl3Plus
      cc-by-40
    ];
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}

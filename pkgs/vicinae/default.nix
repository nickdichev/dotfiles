{
  fetchurl,
  lib,
  stdenvNoCC,
  _7zz,
}:

let
  version = "0.29.1";
in
stdenvNoCC.mkDerivation {
  pname = "vicinae";
  inherit version;

  src = fetchurl {
    url = "https://github.com/vicinaehq/vicinae/releases/download/v${version}/Vicinae.dmg";
    hash = "sha256-6DzvD5rVz/MXLUUgBUUo5PQd59ks0KTAp4kOzk79bh8=";
  };

  sourceRoot = ".";

  unpackPhase = ''
    7zz x -y -snld -x'!Applications' $src
  '';

  nativeBuildInputs = [ _7zz ];

  # Preserve upstream's Developer ID signature and designated requirement so
  # macOS TCC permissions survive package upgrades.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -R Vicinae.app "$out/Applications/"
    ln -s "$out/Applications/Vicinae.app/Contents/MacOS/vicinae-cli" "$out/bin/vicinae"

    runHook postInstall
  '';

  meta = {
    description = "Native, fast, extensible launcher, using the upstream signed application bundle";
    homepage = "https://vicinae.com";
    license = lib.licenses.gpl3Plus;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "vicinae";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}

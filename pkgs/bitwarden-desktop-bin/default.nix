{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  unzip,
}:

stdenv.mkDerivation rec {
  pname = "bitwarden-desktop-bin";
  version = "2026.5.0";

  src = fetchurl {
    url = "https://github.com/bitwarden/clients/releases/download/desktop-v${version}/Bitwarden-${version}-universal-mac.zip";
    hash = "sha256-ToBO47ipnH+ncA+TqhiBOXjYmekjgX4beC47IcBFlQg=";
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    makeWrapper
    unzip
  ];

  dontStrip = true;
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications $out/bin
    cp -R Bitwarden.app $out/Applications/
    makeWrapper $out/Applications/Bitwarden.app/Contents/MacOS/Bitwarden $out/bin/bitwarden

    runHook postInstall
  '';

  meta = {
    description = "Secure and free password manager for all of your devices";
    homepage = "https://bitwarden.com";
    changelog = "https://github.com/bitwarden/clients/releases/tag/desktop-v${version}";
    license = lib.licenses.gpl3;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "bitwarden";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

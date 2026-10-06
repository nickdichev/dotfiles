{
  lib,
  stdenv,
  fetchurl,
  undmg,
}:

let
  version = "1.5.0";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version}-aarch64.dmg";
      hash = "sha256-OSmwpDIefQ9WGjFwWXmL6ILWXezFloHrdwYfjv5W+/Q=";
    };
    x86_64-darwin = {
      url = "https://github.com/rustdesk/rustdesk/releases/download/${version}/rustdesk-${version}-x86_64.dmg";
      hash = "sha256-HKPL++fyvSi1DJP81Q1KC2cdx20YvifOqZ06ZXZ+tSY=";
    };
  };

  src = fetchurl sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "rustdesk";
  inherit version;
  inherit src;

  sourceRoot = ".";

  nativeBuildInputs = [ undmg ];

  dontStrip = true;
  dontPatchShebangs = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r RustDesk.app $out/Applications/
    runHook postInstall
  '';

  meta = {
    description = "Virtual / remote desktop infrastructure for everyone";
    homepage = "https://rustdesk.com";
    license = lib.licenses.agpl3Only;
    platforms = builtins.attrNames sources;
    mainProgram = "RustDesk";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

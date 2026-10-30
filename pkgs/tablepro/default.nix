{
  lib,
  stdenv,
  fetchurl,
}:

let
  version = "0.83.0";
in
stdenv.mkDerivation {
  pname = "tablepro";
  inherit version;

  src = fetchurl {
    # Universal (arm64 + x86_64) app bundle.
    url = "https://github.com/TableProApp/TablePro/releases/download/v${version}/TablePro-${version}.tar.xz";
    hash = "sha256-PioL1eIeFjcQSpyDISm7rtj1MGasWC1INkzJu34mUMI=";
  };

  sourceRoot = ".";

  dontStrip = true;
  dontPatchShebangs = true;
  # Upstream Sparkle.framework ships a dangling XPCServices symlink. The
  # original app still passes codesign/spctl and launches, so preserve it.
  dontCheckForBrokenSymlinks = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R TablePro.app $out/Applications/TablePro.app
    runHook postInstall
  '';

  meta = {
    description = "Native database client for macOS";
    homepage = "https://tableproapp.com";
    license = lib.licenses.unfree;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "TablePro";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

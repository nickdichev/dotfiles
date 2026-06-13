{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:

let
  version = "0.50.0";

  sources = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-RpR4zltGJ/O7K22glRk2TqX0tgkcVy829uEpAIdGCQQ=";
    };
    x86_64-darwin = {
      arch = "x86_64";
      hash = "sha256-O2t6abwPmQaZaH9dviZ4zwbfNPs8IWFnlvaS09+PLkY=";
    };
  };

  source = sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "tablepro";
  inherit version;

  src = fetchurl {
    url = "https://github.com/TableProApp/TablePro/releases/download/v${version}/TablePro-${version}-${source.arch}.zip";
    inherit (source) hash;
  };

  sourceRoot = ".";

  nativeBuildInputs = [ unzip ];

  dontStrip = true;
  dontPatchShebangs = true;
  # Upstream Sparkle.framework ships a dangling XPCServices symlink. The
  # original app still passes codesign/spctl and launches, so preserve it.
  dontCheckForBrokenSymlinks = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R TablePro-${source.arch}.app $out/Applications/TablePro.app
    runHook postInstall
  '';

  meta = {
    description = "Native database client for macOS";
    homepage = "https://tableproapp.com";
    license = lib.licenses.unfree;
    platforms = builtins.attrNames sources;
    mainProgram = "TablePro";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
let
  version = "0.1.17";
  sources = {
    aarch64-darwin = {
      target = "macos-aarch64";
      sha256 = "cedbd4d4d9ba1385588198dd4d3c67d2654478f33add5b6445d4d0eb9da5fcf3";
    };
    x86_64-darwin = {
      target = "macos-x86_64";
      sha256 = "e2dc3211edb1f1c77d0e73dd76c1426636d71050f34a5303916a56d363d7062b";
    };
    aarch64-linux = {
      target = "linux-aarch64";
      sha256 = "3a37a454ec63494cf4306db26481fe9db96673d888723701d24f8a992ae8ab8c";
    };
    x86_64-linux = {
      target = "linux-x86_64";
      sha256 = "82ec44043f6894bfdb716b979b87cda43fd7fa46b0104e7b7bd93e64d1a9b877";
    };
  };
  source = sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "herdr-core";
  inherit version;
  src = fetchurl {
    url = "https://releases.herdr.dev/core/${version}/herdr-core-${source.target}.tar.gz";
    inherit (source) sha256;
  };
  sourceRoot = ".";
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
  dontBuild = true;
  dontStrip = true;
  dontPatchShebangs = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 herdr-core "$out/bin/herdr-core"
    ln -s herdr-core "$out/bin/hc"
    install -Dm644 LICENSE "$out/share/licenses/herdr-core/LICENSE"
    install -Dm644 THIRD-PARTY-NOTICES "$out/share/licenses/herdr-core/THIRD-PARTY-NOTICES"
    runHook postInstall
  '';
  meta = {
    description = "Persistent terminal and coding agent backend for Herdr";
    homepage = "https://github.com/herdrdev/herdr-core";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames sources;
    mainProgram = "herdr-core";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

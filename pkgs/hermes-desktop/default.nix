{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  electron_42,
}:

let
  version = "0.17.0";
  rev = "413ed6b9df18f22152d26b6de4093280dcb2b16b";
in
buildNpmPackage {
  pname = "hermes-desktop";
  inherit version;

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    inherit rev;
    hash = "sha256-wek7P9tdrqRk/ArxBXt/X3BJpQ+wcnKFqG0S+ryx5p0=";
  };

  npmWorkspace = "apps/desktop";
  npmDepsHash = "sha256-RqQyEqzeSlywA83+S9d0KXBnirIVPNFixXCyaE523zo=";

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    GITHUB_SHA = rev;
    GITHUB_REF_NAME = "main";
  };

  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild

    npm run build --workspace apps/desktop

    electron_dist="$PWD/electron-dist"
    cp -R ${electron_42.dist}/. "$electron_dist"
    chmod -R u+w "$electron_dist"

    npm run builder --workspace apps/desktop -- \
      --dir \
      -c.electronDist="$electron_dist" \
      -c.electronVersion=${electron_42.version} \
      -c.mac.identity=null

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications
    cp -R apps/desktop/release/mac-arm64/Hermes.app $out/Applications/
    /usr/bin/codesign --force --deep --sign - $out/Applications/Hermes.app

    runHook postInstall
  '';

  meta = {
    description = "Native desktop client for Hermes Agent";
    homepage = "https://hermes-agent.nousresearch.com/desktop";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "Hermes";
  };
}

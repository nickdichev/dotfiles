{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  electron_42,
}:

let
  version = "0.18.2";
  rev = "9de9c25f620ff7f1ce0fd5457d596052d5159596";
in
buildNpmPackage {
  pname = "hermes-desktop";
  inherit version;

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    inherit rev;
    hash = "sha256-RieWkLWEn21aamFvQTTnJwwQl00JJGgp3LvY3D3G3jQ=";
  };

  npmWorkspace = "apps/desktop";
  npmDepsHash = "sha256-qDXGL/INHPW0pTF4SRVL1dS5XVh2X85dEE4JhrAQeqU=";

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

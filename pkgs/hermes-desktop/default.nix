{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  electron_42,
}:

let
  version = "0.17.6";
  rev = "d337b736aa1e8ebecfab043842d13e4a2d2f48a3";
in
buildNpmPackage {
  pname = "hermes-desktop";
  inherit version;

  src = fetchFromGitHub {
    owner = "NousResearch";
    repo = "hermes-agent";
    inherit rev;
    hash = "sha256-0pfylDk73diMdpQH/YyRWpvon+w4YWBRS3uj8T67qHI=";
  };

  npmWorkspace = "apps/desktop";
  npmDepsHash = "sha256-o8yTDwsr6mbXuUUybvoqS9+jj/xNfJGs58xvYksls6k=";

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

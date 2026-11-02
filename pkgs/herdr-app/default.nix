{
  lib,
  stdenv,
  fetchurl,
  callPackage,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  autoPatchelfHook,
  libxcb,
  libxkbcommon,
  libGL,
  vulkan-loader,
  wayland,
  fontconfig,
}:
let
  version = "0.1.12";
  herdr-core = callPackage ../herdr-core { };
  sources = {
    aarch64-darwin = {
      target = "macos-aarch64";
      sha256 = "006a4f68409a79548d1aa6c5f99da8911b7d14910ef2ac6bd1a3dce634ca5d03";
    };
    aarch64-linux = {
      target = "linux-aarch64";
      sha256 = "749f31d30e3f4d7e24e2748f74d9cb4a9bdda4c968027abaffb6fb239ffeb694";
    };
    x86_64-linux = {
      target = "linux-x86_64";
      sha256 = "a265e6c925c487458406741ffa09d2fa0d3d4bd401a34ed8c01c336108e57c1f";
    };
  };
  source = sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "herdr-app";
  inherit version;
  src = fetchurl {
    url = "https://releases.herdr.dev/app/${version}/herdr-app-${source.target}.tar.gz";
    inherit (source) sha256;
  };
  sourceRoot = if stdenv.hostPlatform.isDarwin then "." else "herdr-app";
  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    copyDesktopItems
  ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    libxcb
    libxkbcommon
  ];
  # GPUI loads graphics, Wayland, and font libraries at runtime.
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    libGL
    vulkan-loader
    wayland
    fontconfig
  ];
  dontBuild = true;
  dontStrip = true;
  dontPatchShebangs = true;
  desktopItems = lib.optionals stdenv.hostPlatform.isLinux [
    (makeDesktopItem {
      name = "herdr-app";
      desktopName = "Herdr";
      comment = "Terminals and coding agents that keep running";
      exec = "herdr-app";
      icon = "herdr-app";
      categories = [
        "Development"
        "TerminalEmulator"
      ];
      startupWMClass = "herdr-app";
    })
  ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    # Preserve the upstream Developer ID signature inside the app bundle.
    mkdir -p "$out/Applications"
    cp -R Herdr.app "$out/Applications/"
    makeWrapper "$out/Applications/Herdr.app/Contents/MacOS/Herdr" "$out/bin/herdr-app" \
      --prefix PATH : "${lib.makeBinPath [ herdr-core ]}"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm755 herdr-app "$out/libexec/herdr-app"
    makeWrapper "$out/libexec/herdr-app" "$out/bin/herdr-app" \
      --prefix PATH : "${lib.makeBinPath [ herdr-core ]}"
    install -Dm644 herdr-app.svg "$out/share/icons/hicolor/scalable/apps/herdr-app.svg"
    install -Dm644 LICENSE "$out/share/licenses/herdr-app/LICENSE"
    install -Dm644 THIRD-PARTY-NOTICES "$out/share/licenses/herdr-app/THIRD-PARTY-NOTICES"
  ''
  + ''
    # Also expose the backend for agents and for the app's login-shell lookup
    # when launched from Finder rather than the CLI wrapper.
    ln -s ${herdr-core}/bin/herdr-core "$out/bin/herdr-core"
    ln -s ${herdr-core}/bin/hc "$out/bin/hc"
    runHook postInstall
  '';
  meta = {
    description = "Native desktop app for terminals and coding agents";
    homepage = "https://github.com/herdrdev/herdr-app";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames sources;
    mainProgram = "herdr-app";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

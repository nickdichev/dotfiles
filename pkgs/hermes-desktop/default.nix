{
  lib,
  stdenvNoCC,
  python3,
  hermes-agent,
  hermes-desktop,
  electron,
  icon,
}:

# Upstream's flake builds the app and its Python backend, but ships them as a
# Linux-style electron wrapper. Repackage that as Hermes.app so macOS shows a
# real app in the Dock and launchers.
stdenvNoCC.mkDerivation {
  pname = "hermes-desktop-app";
  version = hermes-desktop.version;

  dontUnpack = true;
  dontBuild = true;

  nativeBuildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall

    app=$out/Applications/Hermes.app
    mkdir -p $out/Applications
    cp -R ${electron}/Applications/Electron.app $app
    chmod -R u+w $app

    rm -f $app/Contents/Resources/default_app.asar
    # codesign rejects symlinks that leave the bundle, so copy the app in.
    cp -R ${hermes-desktop}/share/hermes-desktop $app/Contents/Resources/app
    cp ${icon} $app/Contents/Resources/hermes.icns

    python3 - $app/Contents/Info.plist <<'EOF'
    import plistlib, sys
    path = sys.argv[1]
    with open(path, "rb") as f:
        info = plistlib.load(f)
    info.update(
        CFBundleName="Hermes",
        CFBundleDisplayName="Hermes",
        CFBundleIdentifier="com.nousresearch.hermes",
        CFBundleIconFile="hermes.icns",
        LSEnvironment={
            "HERMES_DESKTOP_HERMES": "${lib.getExe hermes-agent}",
            "ELECTRON_IS_DEV": "0",
        },
    )
    with open(path, "wb") as f:
        plistlib.dump(info, f)
    EOF

    /usr/bin/codesign --force --deep --sign - $app

    runHook postInstall
  '';

  meta = {
    description = "Native desktop client for Hermes Agent";
    homepage = "https://hermes-agent.nousresearch.com/desktop";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
  };
}

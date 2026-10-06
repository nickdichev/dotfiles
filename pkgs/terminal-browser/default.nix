{
  alsa-lib,
  at-spi2-atk,
  autoPatchelfHook,
  cairo,
  cups,
  dbus,
  expat,
  fetchurl,
  gdk-pixbuf,
  glib,
  gtk3,
  gtk4,
  lib,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libpulseaudio,
  libsecret,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxkbcommon,
  libxkbfile,
  libxrandr,
  libxshmfence,
  nspr,
  nss,
  pango,
  pciutils,
  pipewire,
  speechd-minimal,
  stdenv,
  systemd,
  vulkan-loader,
}:

let
  version = "0.13.4";

  sources = {
    aarch64-darwin = {
      suffix = "darwin-arm64";
      hash = "sha256-8BcjDHjGCgfvRFGh6wqScn8LlVqPzYeuw1iRDF0MA8c=";
    };
    aarch64-linux = {
      suffix = "linux-arm64";
      hash = "sha256-DPVn2CGJlaJPts5LBsB8z1ioxReQYFgIc1Xx4vrRlp8=";
    };
    x86_64-linux = {
      suffix = "linux-x64";
      hash = "sha256-YnfaqrqxZxGrPxlhzf+tnvrF5wrFXVB24shkltZJ06Q=";
    };
  };

  source = sources.${stdenv.hostPlatform.system};

  electronLibraries = [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libgbm
    libGL
    libnotify
    libpulseaudio
    libsecret
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxkbfile
    libxrandr
    libxshmfence
    nspr
    nss
    pango
    pciutils
    pipewire
    speechd-minimal
    stdenv.cc.cc
    systemd
    vulkan-loader
  ];
in
stdenv.mkDerivation {
  pname = "terminal-browser";
  inherit version;

  src = fetchurl {
    url = "https://github.com/zenbu-labs/terminal-browser/releases/download/v${version}/terminal-browser-${source.suffix}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = "terminal-browser";

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux electronLibraries;

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    # Profile symlinks make the launcher's relative root point outside this package.
    substituteInPlace "$out/bin/terminal-browser" \
      --replace-fail 'ROOT="$(CDPATH= cd -- "$(dirname -- "$SELF")/.." && pwd -P)"' "ROOT=\"$out\""
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      /usr/bin/codesign --force --deep --sign - --timestamp=none "$out/electron/terminal-browser.app"
    ''}
    runHook postInstall
  '';

  meta = {
    description = "Browser that runs directly inside a terminal";
    homepage = "https://terminal-browser.com";
    license = lib.licenses.mit;
    platforms = builtins.attrNames sources;
    mainProgram = "terminal-browser";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

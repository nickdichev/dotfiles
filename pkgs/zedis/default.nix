{
  lib,
  stdenv,
  fetchurl,
  _7zz,
  autoPatchelfHook,
  libxcb,
  libxkbcommon,
  libGL,
  vulkan-loader,
  wayland,
}:

let
  version = "0.15.1";

  sources = {
    aarch64-darwin = {
      file = "Zedis-aarch64.dmg";
      hash = "sha256-9Z3l8W6Mty/s6cbcQBGP9msy2yPYLPZlNH7fJHyT2Gw=";
    };
    x86_64-darwin = {
      file = "Zedis-x86_64.dmg";
      hash = "sha256-uiosbscLFSuhvn+XLxdlVZwfXajwkOnOmW1OrPOHt3Q=";
    };
    aarch64-linux = {
      file = "zedis-linux-aarch64.tar.gz";
      hash = "sha256-k3x2Kk15uefnbmizDkyvjbJWU5K7HO/oUtOMy/wRv3k=";
    };
    x86_64-linux = {
      file = "zedis-linux-x86_64.tar.gz";
      hash = "sha256-BdgT+ebV02Yfi1uc92Dw2MKMscw2GdH67UaId3efZHc=";
    };
  };

  source = sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "zedis";
  inherit version;

  src = fetchurl {
    url = "https://github.com/vicanso/zedis/releases/download/v${version}/${source.file}";
    inherit (source) hash;
  };

  sourceRoot = ".";

  nativeBuildInputs =
    lib.optionals stdenv.hostPlatform.isDarwin [ _7zz ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    libxcb
    libxkbcommon
  ];

  # GPUI dlopens its graphics and Wayland libraries at runtime.
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    libGL
    vulkan-loader
    wayland
  ];

  dontStrip = true;
  dontPatchShebangs = true;

  unpackPhase =
    lib.optionalString stdenv.hostPlatform.isDarwin ''
      7zz x -x'!*/Applications' -x'!*/.background' -x'!*/.DS_Store' -x'!*/.VolumeIcon.icns' -x'!*/.fseventsd' $src
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      tar xzf $src
    '';

  # The DMG ships a notarized Developer ID build, so keep its signature intact.
  installPhase = ''
    runHook preInstall
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir -p $out/Applications
    cp -R */Zedis.app $out/Applications/
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm755 zedis $out/bin/zedis
  ''
  + ''
    runHook postInstall
  '';

  meta = {
    description = "Fast, native Redis GUI built with GPUI";
    homepage = "https://github.com/vicanso/zedis";
    license = lib.licenses.asl20;
    platforms = builtins.attrNames sources;
    mainProgram = if stdenv.hostPlatform.isDarwin then "Zedis" else "zedis";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

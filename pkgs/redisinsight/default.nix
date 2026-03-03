{
  lib,
  stdenv,
  fetchurl,
  _7zz,
}:

let
  version = "3.2.0";

  sources = {
    aarch64-darwin = {
      url = "https://github.com/redis/RedisInsight/releases/download/${version}/Redis-Insight-mac-arm64.dmg";
      hash = "sha256-cEK6sJ60erLdfhwK/DWcSi+Wg8xRDmbUyUyxDRGXizw=";
    };
    x86_64-darwin = {
      url = "https://github.com/redis/RedisInsight/releases/download/${version}/Redis-Insight-mac-x64.dmg";
      hash = "sha256-nfQvtUzmzCIPi6aHOW81oTUsZ9TYhNrBHo78U71VYuA=";
    };
  };

  src = fetchurl sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "redisinsight";
  inherit version;
  inherit src;

  sourceRoot = ".";

  nativeBuildInputs = [ _7zz ];

  dontStrip = true;
  dontPatchShebangs = true;

  unpackPhase = ''
    7zz x -x'!Applications' -x'!.background' -x'!.DS_Store' -x'!.VolumeIcon.icns' -x'!.fseventsd' $src
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -r "Redis Insight.app" $out/Applications/
    /usr/bin/codesign --force --deep --sign - "$out/Applications/Redis Insight.app"
    runHook postInstall
  '';

  meta = {
    description = "Developer GUI for Redis";
    homepage = "https://redis.io/insight/";
    license = lib.licenses.unfree;
    platforms = builtins.attrNames sources;
    mainProgram = "Redis Insight";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}

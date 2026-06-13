{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.3.1";

  sources = {
    x86_64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-x86_64-linux";
      hash = "sha256-75Fgb0PFCxchzJIOvReSVnqwJ+xVq8o2UZDmF5jOhc4=";
    };
    aarch64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-aarch64-linux";
      hash = "sha256-08r1gOUJ8YCxpOTAlNsRKIkO2pSPaTXVOlGPbjqSIj0=";
    };
    x86_64-darwin = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-x86_64-macos";
      hash = "sha256-CwKlKA6ks9g3z3jtOtdYtlGsj5lMf9/JQkIIK3Yrrvk=";
    };
    aarch64-darwin = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-aarch64-macos";
      hash = "sha256-nuMWEvPUb/UTBW0CGxXauk8HNowFDeviXoqoUnWHsHQ=";
    };
  };

  src = fetchurl sources.${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "lightpanda";
  inherit version;
  inherit src;

  dontUnpack = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/lightpanda
    runHook postInstall
  '';

  meta = {
    description = "Headless browser designed for AI and automation";
    homepage = "https://github.com/lightpanda-io/browser";
    license = lib.licenses.agpl3Only;
    platforms = builtins.attrNames sources;
    mainProgram = "lightpanda";
  };
}

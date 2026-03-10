{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "0.2.5";

  sources = {
    x86_64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/v${version}/lightpanda-x86_64-linux";
      hash = "sha256:0d7r54yf724fwhqfgg08fvpzx8p16sksxxz244kqk31p370i3a8j";
    };
    aarch64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/v${version}/lightpanda-aarch64-linux";
      hash = "sha256:0mnv2620h06xwbmli8556swby0zk5h346j4n92hmgf8zmmq0h17p";
    };
    x86_64-darwin = {
      url = "https://github.com/lightpanda-io/browser/releases/download/v${version}/lightpanda-x86_64-macos";
      hash = "sha256:0q7yx4xc6rij6h1pvaqj9jvlnr5pr77178d036j67x0g1gwa9325";
    };
    aarch64-darwin = {
      url = "https://github.com/lightpanda-io/browser/releases/download/v${version}/lightpanda-aarch64-macos";
      hash = "sha256:0qdxhy5nwfana3a3q1hr9pc8b7pa7rjfjyyqaqlhcp9c6bywpjrn";
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

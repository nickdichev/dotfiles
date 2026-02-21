{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "nightly";

  sources = {
    x86_64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-x86_64-linux";
      hash = "sha256:1762pc7p8rdanrw4166sj405gs5khnchpf8b7kl0hsy8az9lrh07";
    };
    aarch64-linux = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-aarch64-linux";
      hash = "sha256:0lfwdik9hbpw4q47kfh4aq659ivnls1kv2dim9lsdsizyfl1hgqk";
    };
    x86_64-darwin = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-x86_64-macos";
      hash = "sha256:14d3qwchf9xrszkg0shj0jbgpw7p7djwghinlf2myc0hnhjwdczr";
    };
    aarch64-darwin = {
      url = "https://github.com/lightpanda-io/browser/releases/download/${version}/lightpanda-aarch64-macos";
      hash = "sha256:1rij1hk67g94s2xzb6lvqy4d045pc8v35nmd6py8crzihalqdl35";
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

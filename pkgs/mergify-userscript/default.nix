{
  fetchurl,
  lib,
  stdenvNoCC,
  unzip,
}:

let
  version = "1.6.0";
in
stdenvNoCC.mkDerivation {
  pname = "mergify-userscript";
  inherit version;

  src = fetchurl {
    url = "https://addons.mozilla.org/firefox/downloads/file/5124396/mergify-${version}.xpi";
    hash = "sha256-/SuYo2zHh6BmRAUsqz5rR9qsczqtABlkZW8/r7Q8vdw=";
  };

  nativeBuildInputs = [ unzip ];

  dontUnpack = true;

  # The extension is a single content script that only touches the GitHub DOM
  # and same-origin fetches, so it runs unchanged as a userscript.
  installPhase = ''
    runHook preInstall

    unzip -q "$src" mergify.js
    mkdir -p "$out"
    {
      cat <<'EOF'
    // ==UserScript==
    // @name        Mergify
    // @description Mergify panel for GitHub pull requests (from the Mergify Firefox add-on ${version}, Apache-2.0)
    // @version     ${version}
    // @match       https://github.com/*
    // @run-at      document-idle
    // ==/UserScript==

    EOF
      cat mergify.js
    } > "$out/mergify.user.js"

    runHook postInstall
  '';

  meta = {
    description = "Mergify browser extension repackaged as a userscript for Safari";
    homepage = "https://docs.mergify.com/browser-extensions/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}

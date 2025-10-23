{
  lib,
  stdenv,
  fetchzip,
}:

stdenv.mkDerivation rec {
  pname = "Hammerspoon";
  version = "1.0.0";

  src = fetchzip {
    url = "https://github.com/Hammerspoon/hammerspoon/releases/download/${version}/Hammerspoon-${version}.zip";
    sha256 = "sha256-vqjYCzEXCYBx/gJ32ZNAioruVDy9ghftPAOFMDtYcc0=";
  };

  installPhase = ''
    mkdir -p $out/Applications/Hammerspoon.app
    mv ./* $out/Applications/Hammerspoon.app
    chmod +x "$out/Applications/Hammerspoon.app/Contents/MacOS/Hammerspoon"
  '';

  meta = with lib; {
    description = "Staggeringly powerful macOS desktop automation with Lua.";
    homepage = "https://www.hammerspoon.org";
    maintainers = with maintainers; [ mbaillie ];
    platforms = platforms.darwin;
  };
}

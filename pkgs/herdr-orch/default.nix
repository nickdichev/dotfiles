{
  gh,
  lib,
  makeWrapper,
  symlinkJoin,
  writers,
}:
let
  script = writers.writePython3Bin "herdr-orch" {
    flakeIgnore = [
      "E501"
      "W503"
    ];
  } (builtins.readFile ../../scripts/herdr_orch.py);
in
# herdr and claude come from the user's PATH so they match the versions the
# herdr and ai modules install; gh is a fallback for hosts without it.
symlinkJoin {
  name = "herdr-orch";
  paths = [ script ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/herdr-orch --suffix PATH : ${lib.makeBinPath [ gh ]}
  '';
  meta = {
    description = "Watcher, classifier, token report and benchmark for the herdr-orchestrator skill";
    mainProgram = "herdr-orch";
    platforms = lib.platforms.all;
  };
}

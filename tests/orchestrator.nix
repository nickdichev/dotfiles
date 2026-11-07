# Checks for profiles.ai.orchestrator and herdr-orch, run by `nix flake check`.
#
# The module is evaluated against stubs of the few Home Manager options it
# sets, so bad values are caught without building a whole configuration.
{ pkgs, herdr-orch }:
let
  inherit (pkgs) lib;

  hmStub =
    { lib, ... }:
    {
      options = {
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
        };
        home.packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
        };
        xdg.configFile = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          default = { };
        };
        profiles.ai.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
      };
    };

  eval =
    settings:
    (lib.evalModules {
      modules = [
        ../modules/orchestrator.nix
        hmStub
        { _module.args.pkgs = pkgs; }
        { profiles.ai.orchestrator = settings; }
      ];
    }).config;

  failedAssertions =
    settings: map (a: a.message) (lib.filter (a: !a.assertion) (eval settings).assertions);

  # Bad values the assertions must catch, each with a fragment of the message.
  rejected = {
    unknownModel = {
      settings.tiers.opus.model = "gpt-5";
      expect = "tiers.opus.model";
    };
    bandInverted = {
      settings.classifier.band = {
        low = 0.9;
        high = 0.3;
      };
      expect = "classifier.band";
    };
    bandEmpty = {
      settings.classifier.band = {
        low = 0.5;
        high = 0.5;
      };
      expect = "classifier.band";
    };
    missingTier = {
      settings.workers.implementerTier = "gemini";
      expect = "workers.implementerTier";
    };
    shortFallback = {
      settings.watcher.fallbackCheckMinutes = 10;
      expect = "fallbackCheckMinutes";
    };
    keyInConfig = {
      settings.classifier.apiKeyEnv = "sk-or-v1-abc";
      expect = "apiKeyEnv";
    };
  };

  # Bad values the option types must reject outright.
  typeErrors = {
    unknownEffort.tiers.opus.effort = "huge";
    unknownBackend.classifier.backend = "gpt";
    bandAboveOne.classifier.band.high = 1.5;
    negativePoll.watcher.pollSeconds = 0;
  };

  failures =
    lib.optional (failedAssertions { } != [ ]) "defaults fail: ${toString (failedAssertions { })}"
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: case:
        let
          messages = failedAssertions case.settings;
        in
        lib.optional (
          !(lib.any (lib.hasInfix case.expect) messages)
        ) "${name}: expected an assertion mentioning ${case.expect}, got ${builtins.toJSON messages}"
      ) rejected
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: settings:
        let
          result = builtins.tryEval (builtins.deepSeq (eval settings).profiles.ai.orchestrator true);
        in
        lib.optional result.success "${name}: expected a type error"
      ) typeErrors
    );

  renderedConfig = (eval { }).xdg.configFile."herdr-orchestrator/config.toml".source;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../scripts/herdr_orch.py
      ../tests/test_herdr_orch.py
    ];
  };
in
{
  orchestrator-config =
    if failures == [ ] then
      pkgs.runCommand "orchestrator-config-check" { } "touch $out"
    else
      throw "profiles.ai.orchestrator checks failed:\n${lib.concatStringsSep "\n" failures}";

  herdr-orch-tests = pkgs.runCommand "herdr-orch-tests" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    cd ${src}
    HOME=$TMPDIR HERDR_ORCH_RENDERED_CONFIG=${renderedConfig} python3 -m unittest -v tests/test_herdr_orch.py
    touch $out
  '';

  # Builds the package, which runs flake8 over the script.
  inherit herdr-orch;
}

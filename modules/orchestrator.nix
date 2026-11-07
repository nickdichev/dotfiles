{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.profiles.ai.orchestrator;
  orchestratorLib = import ../lib/orchestrator.nix { inherit lib; };
  inherit (lib) mkOption types;

  defaultTiers = {
    opus = {
      model = "opus";
      effort = "high";
      useFor = "Planning, design, backend/Ash work, hard debugging, and the one review per PR.";
    };
    sonnet = {
      model = "sonnet";
      effort = "medium";
      useFor = "Default implementer: ports that follow an established pattern, mechanical migrations, test fixes, rebases.";
    };
    haiku = {
      model = "haiku";
      effort = "low";
      useFor = "Watching CI, polling PRs, bead bookkeeping, when a script can't do it.";
    };
  };

  tierType = types.submodule {
    options = {
      model = mkOption {
        type = types.str;
        description = "Value for `claude --model`: an alias (opus, sonnet, haiku) or a claude-* model ID.";
      };
      effort = mkOption {
        type = types.enum orchestratorLib.efforts;
        description = "Value for `claude --effort`.";
      };
      useFor = mkOption {
        type = types.str;
        description = "When the orchestrator should pick this tier.";
      };
    };
  };

  int =
    default: description:
    mkOption {
      type = types.ints.positive;
      inherit default description;
    };
  str =
    default: description:
    mkOption {
      type = types.str;
      inherit default description;
    };
  fraction =
    default: description:
    mkOption {
      type = types.numbers.between 0 1;
      inherit default description;
    };
in
{
  options.profiles.ai.orchestrator = {
    enable = lib.mkOption {
      type = types.bool;
      default = config.profiles.ai.enable;
      defaultText = lib.literalExpression "config.profiles.ai.enable";
      description = "Render the herdr-orchestrator config and install herdr-orch.";
    };

    stateDir = str "~/.local/state/herdr-orchestrator" "Ledgers, worker reports, watcher state and the benchmark set.";

    tiers = mkOption {
      type = types.attrsOf tierType;
      default = { };
      description = ''
        Worker tiers by name. The orchestrator records the tier it picks in the
        ledger. opus, sonnet and haiku are defined by default; setting one of
        their fields overrides only that field.
      '';
    };

    workers = {
      implementerTier = str "sonnet" "Default tier for implementation tasks.";
      reviewerTier = str "opus" "Tier for the one review of each finished diff. The benchmark also uses it as the expensive classifier.";
      escalateToTier = str "opus" "Tier to move a task up to after repeated failures.";
      escalateAfterFailures = int 2 "Failures on the same task before moving it to escalateToTier.";
    };

    watcher = {
      pollSeconds = int 30 "How often herdr-orch watch polls Herdr. Polling makes no model calls.";
      idleMinutes = int 10 "A worker idle this long without writing its report gets nudged, then escalated.";
      debounceSeconds = int 60 "A state must hold this long before it counts as a transition.";
      stallMinutes = int 20 "A working worker whose output hasn't changed for this long counts as stalled.";
      prPollSeconds = int 300 "How often to check a recorded PR's checks and mergeability.";
      fallbackCheckMinutes = int 120 "Interval of the orchestrator's one CronCreate fallback, for a dead watcher. Over an hour, so a quiet hour usually costs no orchestrator turn.";
      maxNudges = int 1 "Canned nudges the watcher may send a worker between reports before escalating.";
      reportGraceSeconds = int 120 "How long a new report may wait for the worker's own message before the watcher announces it.";
      waitingMaxMinutes = int 120 "A worker whose report says WAITING_CI or WAITING_REVIEW gets no nudges; after this long the watcher escalates the wait.";
    };

    olive = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Gate "ready" reports on the Olive PR review. For PRs in `repos`, the
          watcher reads Olive's summary comment and sends one OLIVE event when
          every specialist has reported on the PR's current head, and
          `herdr-orch olive <pr>` lists its blocking items.
        '';
      };
      repos = mkOption {
        type = types.listOf types.str;
        default = [ "Portal-Wholesale/cms" ];
        description = "`owner/repo` names whose PRs Olive reviews.";
      };
      marker = str "<!-- olive-pr-specialist-review:v1 -->" "HTML comment that marks Olive's summary comment.";
    };

    classifier = {
      backend = mkOption {
        type = types.enum orchestratorLib.backends;
        default = "off";
        description = ''
          Tier-2 classifier for fuzzy cases (stuck, looping, really finished,
          routine question). `jev` sends redacted terminal output to
          OpenRouter, a third party.
        '';
      };
      band = {
        low = fraction 0.0 "Lower edge of the unsure band. Answers with confidence in [low, high) go to the orchestrator.";
        high = fraction 0.9 "Upper edge of the unsure band. Answers at or above it are acted on without the orchestrator.";
      };
      paneLines = int 60 "Terminal lines sent to the classifier.";
      haikuModel = str "haiku" "Model for the haiku backend.";
      haikuEffort = mkOption {
        type = types.enum orchestratorLib.efforts;
        default = "low";
        description = "Effort for the haiku backend.";
      };
      opusEffort = mkOption {
        type = types.enum orchestratorLib.efforts;
        default = "low";
        description = "Effort when the benchmark runs the reviewer tier as a classifier.";
      };
      jevModel = str "typesafe/jev-1.14" "OpenRouter decision model for the jev backend (hidden from /models; called on /api/alpha/decisions).";
      apiKeyEnv = str "OPENROUTER_API_KEY" "Environment variable holding the OpenRouter key. The key itself never enters the config.";
      timeoutSeconds = int 60 "Per-call classifier timeout.";
    };

    orchestrator = {
      rotateAtPercent = int 35 "Context use at which the watcher tells the orchestrator to write a handoff and restart.";
      contextWindowTokens = int 1000000 "Context window used to compute the orchestrator's context percentage.";
      readLinesMax = int 60 "Most terminal lines the orchestrator may read at once.";
      reportLinesMax = int 40 "Longest allowed worker report file.";
      maxWorkers = int 4 "Most workers running at once.";
    };

    nudges = {
      report = str "Write your report file now at {report} from the template in your brief (status, summary, PR, head, tests, typecheck, open questions, files touched; at most 40 lines), then notify the orchestrator as your brief says and stop. If you are only waiting on CI or a review, use status WAITING_CI or WAITING_REVIEW and don't notify." "Sent to a worker that went idle without a report. {report} is replaced with its path.";
      routine = str "Use your judgement within the brief's scope and continue. Record the choice under open questions in your report." "Sent when the classifier is sure a question is routine.";
      blocked = str "You look stuck or in a loop. Stop retrying. Write your report at {report} with status BLOCKED, what you tried and what you need, then notify the orchestrator and stop." "Sent when the classifier is sure a worker is stuck or looping.";
    };
  };

  config = lib.mkIf cfg.enable {
    profiles.ai.orchestrator.tiers = lib.mapAttrs (_: lib.mapAttrs (_: lib.mkDefault)) defaultTiers;

    assertions = map (message: {
      assertion = false;
      message = "profiles.ai.orchestrator: ${message}";
    }) (orchestratorLib.errors cfg);

    home.packages = [ (pkgs.callPackage ../pkgs/herdr-orch { }) ];

    xdg.configFile."herdr-orchestrator/config.toml".source =
      (pkgs.formats.toml { }).generate "herdr-orchestrator-config.toml"
        (orchestratorLib.toSettings cfg);
  };
}

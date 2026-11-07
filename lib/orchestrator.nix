# Shared by modules/orchestrator.nix and the flake's checks: turn
# `profiles.ai.orchestrator` into the TOML that herdr-orch and the
# herdr-orchestrator skill read, and list what is wrong with it.
{ lib }:
rec {
  modelAliases = [
    "opus"
    "sonnet"
    "haiku"
    "fable"
  ];

  efforts = [
    "low"
    "medium"
    "high"
    "xhigh"
    "max"
  ];

  backends = [
    "off"
    "haiku"
    "jev"
  ];

  # `claude --model` takes an alias or a full model ID.
  knownModel =
    model: lib.elem model modelAliases || builtins.match "claude-[a-z0-9.-]+([[]1m[]])?" model != null;

  # Errors that option types can't express. Empty means valid.
  errors =
    cfg:
    let
      tierNames = lib.attrNames cfg.tiers;
      tierRef =
        name: value:
        lib.optional (
          !(lib.elem value tierNames)
        ) "workers.${name} = \"${value}\" is not a declared tier (${lib.concatStringsSep ", " tierNames})";
    in
    lib.optional (cfg.tiers == { }) "declare at least one tier"
    ++ lib.concatLists (
      lib.mapAttrsToList (
        name: tier:
        lib.optional (!(knownModel tier.model))
          "tiers.${name}.model = \"${tier.model}\" is not a Claude model alias (${lib.concatStringsSep ", " modelAliases}) or claude-* ID"
        ++ lib.optional (
          !(lib.elem tier.effort efforts)
        ) "tiers.${name}.effort = \"${tier.effort}\" is not one of ${lib.concatStringsSep ", " efforts}"
      ) cfg.tiers
    )
    ++ tierRef "implementerTier" cfg.workers.implementerTier
    ++ tierRef "reviewerTier" cfg.workers.reviewerTier
    ++ tierRef "escalateToTier" cfg.workers.escalateToTier
    ++
      lib.optional (!(lib.elem cfg.classifier.backend backends))
        "classifier.backend = \"${cfg.classifier.backend}\" is not one of ${lib.concatStringsSep ", " backends}"
    ++
      lib.optional
        (
          !(
            cfg.classifier.band.low >= 0
            && cfg.classifier.band.low < cfg.classifier.band.high
            && cfg.classifier.band.high <= 1
          )
        )
        "classifier.band needs 0 <= low < high <= 1 (got ${toString cfg.classifier.band.low}..${toString cfg.classifier.band.high})"
    ++ lib.optional (
      !(knownModel cfg.classifier.haikuModel)
    ) "classifier.haikuModel = \"${cfg.classifier.haikuModel}\" is not a Claude model"
    ++ lib.optional (
      builtins.match "[A-Z_][A-Z0-9_]*" cfg.classifier.apiKeyEnv == null
    ) "classifier.apiKeyEnv must name an environment variable, not hold a key"
    ++
      lib.optional (cfg.watcher.fallbackCheckMinutes < 60)
        "watcher.fallbackCheckMinutes must be at least 60; the watcher, not a heartbeat, wakes the orchestrator"
    ++ lib.optional (
      cfg.watcher.stallMinutes <= cfg.watcher.debounceSeconds / 60
    ) "watcher.stallMinutes must exceed the debounce"
    ++ lib.optional (
      !(cfg.orchestrator.rotateAtPercent > 0 && cfg.orchestrator.rotateAtPercent < 100)
    ) "orchestrator.rotateAtPercent must be between 0 and 100"
    ++ lib.optional (cfg.olive.enable && cfg.olive.marker == "") "olive.marker must be set when olive is enabled"
    ++ map (repo: "olive.repos: \"${repo}\" is not owner/repo") (
      lib.filter (repo: builtins.match "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+" repo == null) cfg.olive.repos
    );

  # The rendered file uses snake_case keys; scripts/herdr_orch.py reads them.
  toSettings = cfg: {
    paths.state_dir = cfg.stateDir;
    tiers = lib.mapAttrs (_: tier: {
      inherit (tier) model effort;
      use_for = tier.useFor;
    }) cfg.tiers;
    workers = {
      implementer_tier = cfg.workers.implementerTier;
      reviewer_tier = cfg.workers.reviewerTier;
      escalate_to_tier = cfg.workers.escalateToTier;
      escalate_after_failures = cfg.workers.escalateAfterFailures;
    };
    watcher = {
      poll_seconds = cfg.watcher.pollSeconds;
      idle_minutes = cfg.watcher.idleMinutes;
      debounce_seconds = cfg.watcher.debounceSeconds;
      stall_minutes = cfg.watcher.stallMinutes;
      pr_poll_seconds = cfg.watcher.prPollSeconds;
      fallback_check_minutes = cfg.watcher.fallbackCheckMinutes;
      max_nudges = cfg.watcher.maxNudges;
      report_grace_seconds = cfg.watcher.reportGraceSeconds;
      waiting_max_minutes = cfg.watcher.waitingMaxMinutes;
    };
    olive = {
      inherit (cfg.olive) enable repos marker;
    };
    classifier = {
      inherit (cfg.classifier) backend;
      band_low = cfg.classifier.band.low;
      band_high = cfg.classifier.band.high;
      pane_lines = cfg.classifier.paneLines;
      haiku_model = cfg.classifier.haikuModel;
      haiku_effort = cfg.classifier.haikuEffort;
      opus_effort = cfg.classifier.opusEffort;
      jev_model = cfg.classifier.jevModel;
      api_key_env = cfg.classifier.apiKeyEnv;
      timeout_seconds = cfg.classifier.timeoutSeconds;
    };
    orchestrator = {
      rotate_at_percent = cfg.orchestrator.rotateAtPercent;
      context_window_tokens = cfg.orchestrator.contextWindowTokens;
      read_lines_max = cfg.orchestrator.readLinesMax;
      report_lines_max = cfg.orchestrator.reportLinesMax;
      max_workers = cfg.orchestrator.maxWorkers;
    };
    inherit (cfg) nudges;
  };
}

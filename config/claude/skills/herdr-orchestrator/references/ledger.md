# Ledger

`<state_dir>/<HERDR_WORKSPACE_ID>/<slug>.json` is the run's source of truth and the orchestrator's memory across restarts. `clean-stale-herdr` and `herdr-orch` read it. The orchestrator writes it, except for the fields marked *(watcher)* or *(record-usage)*.

```json
{
  "slug": "<slug>",
  "source": "<epic id or plan path>",
  "workspace_id": "<HERDR_WORKSPACE_ID>",
  "orchestrator_pane": "<HERDR_PANE_ID>",
  "orchestrator_agent": "orch-<slug>",
  "watcher_pane": "<pane running herdr-orch watch>",
  "fallback_job": "<CronCreate job id>",
  "started_at": "<ISO timestamp>",
  "closed_at": null,
  "rotate_requested": false,
  "rotations": 0,
  "workers": [
    {
      "name": "<slug>-<task>",
      "task": "<bead id or plan step>",
      "role": "implement|review|other",
      "tier": "<tier name from config>",
      "model": "<tier.model>",
      "effort": "<tier.effort>",
      "recipe": null,
      "tab_id": "...",
      "pane_id": "...",
      "cwd": "...",
      "worktree": null,
      "status": "running|done|failed|closed",
      "failures": 0,
      "prs": [],
      "started_at": "...",
      "updated_at": "...",
      "finished_at": null,
      "session_ids": [],
      "usage": null,
      "usage_source": null
    }
  ],
  "decisions": [],
  "escalations": [],
  "handoff": null
}
```

- `status: running` is the only status the watcher watches. Set `done`, `failed` or `closed` as soon as that is true.
- `prs`: add a worker's PR URLs here (they also come from its report). The watcher polls their checks and mergeability.
- `failures`: failed attempts on this task, which drive the escalation to `workers.escalate_to_tier`. When you relaunch a task on a higher tier, add a new worker entry and set the old one to `failed`.
- *(record-usage)* `finished_at`, `session_ids`, `usage` and `usage_source`: `herdr-orch record-usage --ledger <ledger> --worker <name>` fills these in from the worker's Claude transcripts, as token totals by model. If no transcript is found, `usage` stays null and `usage_source` says why.
- *(watcher)* `rotate_requested` and `rotations`: the watcher clears `rotate_requested` after it restarts you.
- `closed_at`: setting it stops the watcher.

The run directory `<state_dir>/<HERDR_WORKSPACE_ID>/<slug>/` holds:

- `<worker>.report.md`: worker reports;
- `watch-state.json`: watcher state, `heartbeat_at`, and the session IDs it has seen for each agent;
- `classifier.jsonl`: one line per tier-2 classification (label, confidence, cost; no terminal text).

## Handoff

Write this before every rotation. It is all that survives the restart besides the ledger itself and the plan.

```json
"handoff": {
  "written_at": "<ISO timestamp>",
  "state": "on track | at risk | blocked",
  "decisions": ["<decision in force and why, one line each>"],
  "in_flight": ["<worker> → <task> (<tier>): <where it stands>"],
  "next": ["<the next concrete step>"],
  "watch_for": ["<anything easy to forget, e.g. 'PR 12 needs review once CI is green'>"]
}
```

Keep it to about 15 lines. If it needs more, the ledger's `decisions` and `workers` should hold that detail instead.

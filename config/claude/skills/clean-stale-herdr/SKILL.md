---
name: clean-stale-herdr
description: Close stale Herdr worker agents, panes, and tabs that a herdr-orchestrator run created in the current Herdr workspace. Use when the user asks to clean up stale Herdr sessions or orchestrator workers, or when a herdr-orchestrator run finishes.
argument-hint: "[run slug]"
---

# Clean Stale Herdr

Close the Herdr panes and tabs left behind by `herdr-orchestrator` runs. Only touch the current workspace, and only touch what an orchestrator created.

Load the `herdr` skill first and follow its safety rules. Check that you are inside Herdr (`test "${HERDR_ENV:-}" = 1`); if not, say so and stop.

## 1. Scope

- **Workspace**: only `$HERDR_WORKSPACE_ID`. Never close panes or tabs in another workspace, and never close a workspace.
- **Runs**: the ledgers in `<state_dir>/$HERDR_WORKSPACE_ID/*.json`, where `state_dir` is `[paths].state_dir` in `herdr-orch config` (normally `~/.local/state/herdr-orchestrator`). Skip ledgers that already have `closed_at` and no live panes. If the user passed a run slug (`$ARGUMENTS`), use only that ledger. If you are the orchestrator, use your own run's ledger.
- **Never close** your own pane (`$HERDR_PANE_ID`), the tab that contains it, or the orchestrator pane of a run that is still active.

If there are no ledgers, you may fall back to naming conventions: tabs labelled `<slug>:*` and agents named `<slug>-*`, but only when the user named the slug. Otherwise report that there is nothing to clean.

## 2. Inventory

```bash
herdr pane list --workspace "$HERDR_WORKSPACE_ID"
herdr tab list --workspace "$HERDR_WORKSPACE_ID"
herdr agent list
```

Match the live panes and tabs against the ledger's `workers[].pane_id` / `tab_id`, its `watcher_pane`, and tabs labelled `<slug>:*` (including the `<slug>:watch` tab). Ignore any match whose `workspace_id` is not `$HERDR_WORKSPACE_ID`.

## 3. Decide what is stale

A pane is stale if it belongs to the run and any of the following holds:

- Its ledger status is `done`, `failed`, or `closed`.
- Its agent is gone (the pane is a plain shell at the prompt), or the agent is `idle`/`done` and its task is finished: the bead is closed (`bd show <id>`) or the ledger marks it complete.
- The whole run is finished: the ledger has `closed_at`, or its orchestrator pane no longer exists, or no workers are still `working`.

The watcher pane (`watcher_pane`, running `herdr-orch watch`) is stale once the run is finished. It exits by itself when `closed_at` is set; if it is still running, stop it with `ctrl+c`.

A pane is **not** stale if its agent is `working` or `blocked`, or if its task is still open in an active run. Check with `herdr agent read <pane> --source recent-unwrapped --lines 60` before closing anything ambiguous, and leave it alone if unsure.

Before closing a pane, look for work that would be lost: uncommitted changes in its cwd or worktree (`git -C <cwd> status --porcelain`). If there are any, don't close it; report it.

## 4. Close

If the plan closes more than a handful of panes, or any pane the ledger doesn't explicitly mark `done`, show the plan and get confirmation first. Otherwise go ahead.

- If an agent is still running in a pane you're closing, send it `ctrl+c` (`herdr agent send-keys <name> ctrl+c`), then close the pane with `herdr pane close <pane_id>`.
- Close a tab with `herdr tab close <tab_id>` once every pane in it is stale.
- For each worker you closed, set the ledger status to `closed`. Once nothing remains, set `closed_at` (if it isn't set). Keep the ledger and its run directory `<state_dir>/$HERDR_WORKSPACE_ID/<slug>/`: `herdr-orch report <slug>` reads them to compare runs. If the run's `fallback_job` cron job belongs to this session, delete it with `CronDelete`.
- Don't remove git worktrees or branches. List them in the report so the user can decide.

## 5. Report

List what was closed (tab and pane IDs with worker names), what was kept and why (still working, uncommitted changes, ambiguous), and any worktrees that are still around.

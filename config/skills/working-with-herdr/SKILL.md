---
name: working-with-herdr
description: Inspect and control Herdr terminal workspaces, tabs, panes, and interactive coding agents through the Herdr CLI. Use when the user asks to find panes in the current Herdr tab, inspect pane layouts or agent state, create or focus splits, launch Codex through the cdx wrapper, send prompts to agents, wait for completion, or read agent output.
---

# Working with Herdr

Use Herdr's structured CLI commands to coordinate terminal panes and coding agents. Inspect live state before targeting a pane, and use pane IDs returned by Herdr rather than guessing.

## Discover the Session

1. Confirm that the client and server are available:

   ```bash
   herdr status
   ```

2. Identify the caller's pane and current tab:

   ```bash
   herdr pane current
   herdr pane layout --current
   ```

3. Use the layout's `panes` array to find sibling pane IDs in the current tab. Use broader listings only when the task spans tabs or workspaces:

   ```bash
   herdr pane list
   herdr agent list
   ```

4. Inspect a target before acting on it:

   ```bash
   herdr pane get <pane-id>
   herdr pane process-info --pane <pane-id>
   herdr agent get <pane-id>
   ```

Call `<command> --help` when a subcommand or option is uncertain; the installed CLI is authoritative.

## Create a Split

Split from an explicit pane when its ID is already known. Otherwise use `--current` only after confirming the current pane:

```bash
herdr pane split --current \
  --direction down \
  --ratio 0.5 \
  --cwd "$PWD" \
  --no-focus
```

Use `right` for a side-by-side split. Record `result.pane.pane_id` from the JSON response; use that ID for every subsequent operation. Preserve the working directory and leave focus unchanged unless the user asks otherwise.

## Start Codex

When the user requests this setup's `cdx` wrapper, type it into the new interactive shell:

```bash
herdr pane send-text <pane-id> cdx
herdr pane send-keys <pane-id> enter
herdr agent wait <pane-id> \
  --until idle \
  --until done \
  --until blocked \
  --timeout 30000
```

`cdx` is a zsh alias for `codex --profile home-manager --yolo`, not an executable. Do not try to launch it with `herdr agent start` or `herdr pane run`.

When the wrapper is not required, prefer Herdr's lifecycle-aware canonical launcher:

```bash
herdr agent start <agent-name> \
  --kind codex \
  --pane <pane-id> \
  -- --profile home-manager --yolo
```

The target pane must be at an interactive shell prompt.

## Prompt and Observe an Agent

Check the target first. If it is already working, do not send another prompt unless the user explicitly intends to redirect or queue work.

Submit a prompt and wait for a settled state:

```bash
herdr agent prompt <pane-id> "<message>" \
  --wait \
  --until idle \
  --until done \
  --until blocked \
  --timeout 120000
```

Only use `--wait` after confirming the agent was not already working. A wait started against a working agent may observe completion of its existing turn rather than the newly submitted work.

Read recent output without changing the pane:

```bash
herdr agent read <pane-id> \
  --source recent-unwrapped \
  --lines 120
```

Use `herdr pane read <pane-id>` when shell startup or non-agent terminal output is relevant.

## Guardrails

- Treat `current`, `layout`, `list`, `get`, `process-info`, and `read` as discovery commands; inspect before mutating terminal state.
- Create splits, launch processes, send prompts, or change focus only within the user's requested scope.
- Do not close, move, swap, resize, interrupt, or reuse an existing pane without explicit authorization.
- Do not target a pane by screen position alone. Resolve its current pane ID from the live layout.
- Prefer `--no-focus` for background agents so the user's active pane remains stable.
- Use bounded waits and provide progress updates during long agent turns.
- Avoid reproducing unrelated terminal output that may contain secrets or private context.
- Report the target pane ID, final agent state, and concise result after an operation.

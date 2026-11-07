# Worker brief

Write each brief from this outline. The worker can't see your conversation, so the brief must stand on its own. Keep it short: link the plan, bead or recipe instead of pasting it.

```markdown
You are <slug>-<task>, a worker in orchestrator run <slug>. Work only in <cwd or worktree>.

## Task
<goal, and the bead or plan step>. <acceptance criteria>.
<context from the plan that the worker can't infer>
<if a recipe applies: Follow recipe <path> for <target>.>

## Out of scope
<what not to touch, and which files or areas belong to other workers>

## Verify
<tests, build or lint commands to run before reporting DONE>

## Beads (beads work only)
Run `bd update <id> --status in_progress` when you start, and close the bead when done.

## Report back
When you finish, get stuck, or need a decision:
1. Write <run dir>/<slug>-<task>.report.md from this template (at most <report_lines_max> lines), overwriting any earlier report:
   <the template from report-template.md>
2. Then run `herdr agent prompt orch-<slug> "[<slug>-<task>] <DONE|BLOCKED|QUESTION>: <one-line summary>"`, and stop and wait.
Don't ask the user directly; the orchestrator relays anything that needs them. Never merge or deploy.
```

A review worker's brief replaces **Task** and **Verify** with: review PR `<url>` against the acceptance criteria and the recipe's done criteria, comment on the PR, and report `DONE` with the verdict in `summary` (approve, or changes needed with a count).

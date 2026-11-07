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
If a scoped typecheck still shows errors, run the same scoped command on the base (the merge base, in a separate worktree) and report "<N> errors on head vs <M> on base, none new" in the report's `typecheck` field.

## Beads (beads work only)
Run `bd update <id> --status in_progress` when you start, and close the bead when done.

## Report back
When you finish, get stuck, or need a decision:
1. Write <run dir>/<slug>-<task>.report.md from this template (at most <report_lines_max> lines), overwriting any earlier report:
   <the template from report-template.md>
2. Then run `herdr agent prompt orch-<slug> "[<slug>-<task>] <DONE|BLOCKED|QUESTION>: <one-line summary>"`, and stop and wait.
If you have pushed and only CI or a review is left, write the report with status WAITING_CI or WAITING_REVIEW and `head` set, skip step 2, and stop. Don't use BLOCKED for a wait, and don't poll CI.
Don't ask the user directly; the orchestrator relays anything that needs them. Never merge or deploy.
```

## Review brief

A review worker's brief replaces **Task** and **Verify** with: review PR `<url>` at head `<sha>` against the acceptance criteria and the recipe's done criteria, comment on the PR, and report `DONE` with the verdict in `summary` (approve, or changes needed with a count of blocking items). Always include this checklist:

```markdown
## Checklist (answer each in your PR comment)
- Parity, per-viewer state: list every viewer-dependent field the old code computed (saved, claimed, permissions, and anything else read from the session or user). For each, show where the new code restores it, or flag it as blocking. A field hard-coded to a default (for example `is_saved: false`) counts as not restored.
- Public surface: does the PR add or widen an anonymous or public endpoint, action, argument bound or visible field set? Give the bound and who can reach it.
- Visibility: does any filter differ from the old code's (archived, test, deleted, unpublished)? Say which rows are now exposed, and through which fields.
```

## Fix brief

For a fix round, start a **fresh** implementer (never the original session) with:

```markdown
You are <slug>-<task>-fix<N>, a worker in orchestrator run <slug>. Work only in <worktree>, on branch <branch>.

## State (from the orchestrator)
PR: <url>, head <sha>. <≤10 lines: what the PR does, validation commands used, decisions the fix must not undo.>

## Fix
Answer these review comments: <reviewer comment URL>, <Olive comment URL>.
Items to fix (each needs a commit, or a reason it is wrong):
1. <[source] item, one line>
…
Don't widen an anonymous or public surface, relax a bound, or change visibility to fix an item. If a fix seems to need that, stop and report QUESTION with the options.

## Verify
<the same commands as the original brief>

## Report back
<as in the main brief. In `summary`, map each item to its commit SHA or reason. Push, then report WAITING_CI with `head` set.>
```

## Fix re-review brief

After a fix round, start a **fresh** reviewer on `workers.reviewer_tier`:

```markdown
You are <slug>-<task>-rereview<N>. Review only the fix commits on PR <url>: `git diff <pre_fix_head>..<new head>`, in <worktree>. Don't re-review the rest of the PR.
For each item below, check that its commit does what it claims: <the fix list, with the commits from the fix report>.
Then answer explicitly: did any fix widen an anonymous or public surface, relax a bound, or change visibility? Name the file and line, the old and new value, and who can now reach it. Any "yes" is blocking.
Comment on the PR, then report DONE with the verdict in `summary` (clean, or N blocking).
```

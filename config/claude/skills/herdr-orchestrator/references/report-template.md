# Worker report

Workers write this file before notifying the orchestrator, and overwrite it each time they report. It is the only thing the orchestrator reads from them. Keep it within the config's `orchestrator.report_lines_max` lines. The first line must be the status line: the watcher parses it, and the PR URLs.

```markdown
status: DONE | BLOCKED | QUESTION | WAITING_CI | WAITING_REVIEW
summary: <one line: what is true now>
pr: <PR URL, or none>
head: <full SHA of the commit this report describes, or none>
tests:
- <command>: pass | fail | not run (<one-line detail>)
typecheck: <scope>: clean | <N> errors on head vs <M> on base (<base sha12>), none new | new: <file:line, …> | not run (<why>)
open_questions:
- <question, with the options and your recommendation> | none
files_touched: <count>
```

- **DONE**: the acceptance criteria hold, and the tests listed passed.
- **BLOCKED**: you can't continue. Say what you tried and what you need. Never use it for a wait.
- **QUESTION**: you need a decision. Put it under `open_questions`.
- **WAITING_CI**: your work on `head` is pushed and only CI is left. Don't notify the orchestrator and don't poll CI: stop. The watcher wakes the orchestrator when CI finishes on that head, and it tells you if CI failed.
- **WAITING_REVIEW**: your work on `head` is pushed and you are waiting for a review (Olive or a review worker). Same rules as `WAITING_CI`.

**`typecheck`** is required whenever the scoped typecheck still shows errors. Run the same scoped command on the base (the PR's merge base, in a separate worktree) in the same round, and report both counts. "None new" means every error on head also appears on base. Without the base count, the orchestrator treats the report as unverified.

Don't paste diffs, logs or terminal output into the report. Give the command and the result, and the orchestrator can look further if it needs to.

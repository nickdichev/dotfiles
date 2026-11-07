# Worker report

Workers write this file before notifying the orchestrator, and overwrite it each time they report. It is the only thing the orchestrator reads from them. Keep it within the config's `orchestrator.report_lines_max` lines. The first line must be the status line: the watcher parses it, and the PR URLs.

```markdown
status: DONE | BLOCKED | QUESTION
summary: <one line: what is true now>
pr: <PR URL, or none>
tests:
- <command>: pass | fail | not run (<one-line detail>)
open_questions:
- <question, with the options and your recommendation> | none
files_touched: <count>
```

- **DONE**: the acceptance criteria hold, and the tests listed passed.
- **BLOCKED**: you can't continue. Say what you tried and what you need.
- **QUESTION**: you need a decision. Put it under `open_questions`.

Don't paste diffs, logs or terminal output into the report. Give the command and the result, and the orchestrator can look further if it needs to.

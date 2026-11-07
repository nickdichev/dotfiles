# Watcher events

`herdr-orch watch` polls Herdr, the run's report files and GitHub every `watcher.poll_seconds`, without model calls. When something changes it prompts you with one line. Several events from the same poll arrive together, separated by ` | `. Each event is sent once: the watcher keeps its state in `<run dir>/watch-state.json`, so a restart doesn't replay old events.

| Event | Meaning | Respond |
|---|---|---|
| `[watch] <w> REPORT status=S report=<path> (worker did not notify)` | The report changed, and the worker's own `[<w>]` message didn't arrive within `watcher.report_grace_seconds`. | Read the report and act on its status, as for a worker message. |
| `[watch] <w> IDLE_NO_REPORT for Nm` | Idle without a report, even after the watcher's canned "write your report" nudge. | Read up to `read_lines_max` pane lines, then re-prompt the worker or replace it. |
| `[watch] <w> BLOCKED (waiting on a prompt)` | Claude is showing a question or permission UI. | Read the pane, then answer with `agent prompt` or `agent send-keys`, or escalate. |
| `[watch] <w> STALLED (no new output for Nm)` | Working, but its output hasn't changed for `watcher.stall_minutes`. | Read the pane. If it's waiting on something long, leave it; if it's wedged, send `esc`/`ctrl+c` and re-brief it. |
| `[watch] <w> GONE` / `UNKNOWN state` | The agent left its pane, or Herdr can't tell its state. | Check the pane; relaunch with `dc` if needed. |
| `[watch] <w> PR <url> head=<sha12> state=… checks=… merge=…` | A tracked PR's checks finished on that head, it became conflicted, or it merged or closed. | `fail` → the worker fixes CI; `CONFLICTING` → the worker rebases; `pass` → the next PR gate. Never "ready" on this event alone. |
| `[watch] <w> OLIVE <url> head=<sha12> reports=N/N blocking=K` | Olive's summary comment shows every specialist report for the PR's current head. Sent once per head. | Run the Olive gate (`herdr-orch olive <url>`) and triage each blocking item. |
| `[watch] <w> WAITING_CI\|WAITING_REVIEW for Nm (over Lm)` | The worker's report has said it is waiting for longer than `watcher.waiting_max_minutes`. | Check the PR's checks or the review; re-run CI, chase the reviewer, or re-brief the worker. |
| `[watch] <w> <REASON> unsure label=L conf=C` | Tier 2: the classifier's confidence fell in the unsure band. | Treat it as the matching escalation above. |
| `[watch] <w> <REASON> label=real_question …` | Tier 2: a question that needs you. | Read the pane and decide, or escalate. |
| `[watch] orchestrator ROTATE ctx=N%` | Your context passed `orchestrator.rotate_at_percent`. | Follow Rotate in SKILL.md. |

## Heads and waits

- **Stale heads**: PR and Olive events carry the head SHA they describe. Just before sending, the watcher re-reads the PR's head and drops any event whose head has moved on (it logs the drop). A new head gets its own events.
- **Waiting workers**: while a worker's latest report says `WAITING_CI` or `WAITING_REVIEW` and it hasn't started working again since, the watcher doesn't announce that report and sends it no idle or stall nudges. It still reports `GONE`, `UNKNOWN` and permission prompts, and escalates a wait over `watcher.waiting_max_minutes`.
- **Olive**: for PRs in `olive.repos`, the watcher reads Olive's summary comment (the one with `olive.marker`) at each PR poll. A partial review, or one of an older head, sends nothing.

## Tier 2 (only when `classifier.backend` isn't `off`)

For blocked, idle-without-report and stalled workers, the watcher first sends the last `classifier.pane_lines` lines (redacted) to the classifier. The classifier picks one of `working`, `finished`, `stuck`, `looping`, `routine_question` or `real_question`, with a confidence.

- If the confidence falls in `[band_low, band_high)`, the case is escalated to you as `unsure`.
- Otherwise the watcher trusts the label:
  - `working`: it does nothing.
  - `finished`: it nudges the worker to write its report.
  - `routine_question`: it tells the worker to use its judgement and continue.
  - `stuck` or `looping`: it tells the worker to stop and write a BLOCKED report.
  - `real_question`: it always escalates to you.
- At most `watcher.max_nudges` nudges go to a worker between reports. After that, the watcher escalates instead.

The nudge texts come from the config's `[nudges]`. Every classification goes to `<run dir>/classifier.jsonl`.

## Sessions and context

Each poll, the watcher records the Claude session ID Herdr reports for each agent; `herdr-orch report` and `record-usage` use these IDs to find the transcripts. The watcher also reads the tail of your own transcript, to compute your context use and to see which workers have already messaged you.

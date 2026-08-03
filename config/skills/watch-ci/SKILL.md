---
name: watch-ci
description: Watch GitHub pull request checks for the current branch, notify the user when CI succeeds, and investigate failures. Use when the user asks to watch, monitor, babysit, or wait for CI/checks on a pull request or branch.
---

# Watch CI

## Workflow

1. Confirm the current directory is inside a Git repository:

   ```bash
   git rev-parse --show-toplevel
   ```

2. Resolve the pull request for the current branch and record its number, title, URL, and repository:

   ```bash
   gh pr view --json number,title,url,headRefName
   gh repo view --json nameWithOwner --jq .nameWithOwner
   ```

   Stop and explain the problem if the branch has no pull request or `gh` is not authenticated.

3. Watch all checks through completion. Do not use `--fail-fast`; later failures may contain useful diagnostic information.

   ```bash
   gh pr checks --watch --interval 10
   ```

   Keep the user informed during a long watch and continue polling an ongoing command/session until the checks reach a terminal state.

4. Query the final structured result rather than inferring it from terminal formatting:

   ```bash
   gh pr checks --json name,state,bucket,link,workflow
   ```

5. If at least one check is present and every check is in `pass` or `skipping`, send a desktop notification and report the green result with the PR URL. Prefer an available native notification command (`terminal-notifier`, macOS `osascript`, or `notify-send`); also report the result in the conversation. Keep the notification free of secrets. If no checks are present, report that state instead of calling it green.

6. If any check is in `fail` or `cancel`, report which checks failed and investigate:

   - Treat the repository as a Portal-Wholesale project when `gh repo view --json nameWithOwner --jq .nameWithOwner` begins with `Portal-Wholesale/`, or as a fallback when its Git root is under `~/Workspace/portal/`.
   - For a Portal-Wholesale project, load and follow the `working-with-nixbot` skill (`$working-with-nixbot` in Codex). Pass along the PR and failed-check context.
   - For another GitHub repository, inspect the failed check links and use `gh run view <run-id> --log-failed` for GitHub Actions failures when a run ID is available. Summarize the actionable cause; do not edit code unless the user asked for a fix.

7. Send a desktop notification after failure triage, then report the outcome, failing checks, and diagnostic findings in the conversation.

## Notification Examples

Use a short, static message when no richer notification facility is available:

```bash
/usr/bin/osascript -e 'display notification "Pull request checks passed" with title "CI complete"'
```

```bash
notify-send "CI complete" "Pull request checks passed"
```

Adapt the message for failed checks. Never interpolate untrusted check output into shell code.

---
description: Format, lint, and review a PR from Chance before merging
argument-hint: <the PR number>
allowed-tools: Bash(just:*), Edit, Write, Read
---

## Context

- Working directory: `backend/` for changes in the PR in `backend/`, `frontend/` for changes in the PR in `frontend/`
- Use `just` commands for running scripts and tasks where possible

## Task

Checkout the PR #"$ARGUMENTS" from Github, apply our formatting and linting standards, and review the changes.: 

1. Checkout the PR branch from Github using `gh pr checkout "$ARGUMENTS"`
2. Run `oxfmt` from the `frontend/` directory to format the code
3. Run `oxlint` from the `frontend/` directory and check for linting issues. If there are any, fix them.
4. Commit any formatting or linting changes.
5. Review the changes in the PR for correctness, style, and adherence to project guidelines. Make an extra focus on the following common issues:
    - data migrations applied in a schema migration
    - excessive client side mangling of data that could be done server side, especially where it impacts performance, creates n+1 queries, or increases complexity
    - missing or inadequate tests for new features or bug fixes
6. Check if this PR can be applied independently, or if it relies on other unmerged PRs. If it relies on other unmerged PRs, leave a comment indicating that those PRs need to be merged first.
7. Leave comments on the PR for any issues found during the review.
8. If no issues are found, approve the PR using `gh pr review "$ARGUMENTS" --approve`

---
name: working-with-nixbot
description: Investigate Portal-Wholesale Nixbot CI checks and build failures through GitHub, the Nixbot API, and build logs. Use whenever the user mentions Nixbot or nixbot, asks about Portal-Wholesale CI/build failures, or a Portal repository has a failing Nixbot check.
---

# Working with Nixbot

Nixbot runs CI checks for Portal-Wholesale pull requests and reports them as GitHub status checks.

## Service

- UI: `https://nixbot.tailb22a98.ts.net`
- API: `https://nixbot.tailb22a98.ts.net/api`
- Live OpenAPI document: `https://nixbot.tailb22a98.ts.net/api/openapi.json`

Fetch the live OpenAPI document when the current contract or an unfamiliar endpoint is needed. Do not assume the old `/api/v2/builders/...` routes work; the service uses repository/build endpoints.

## Investigate a Pull Request

1. List the pull request checks. With no argument, `gh` selects the pull request for the current branch:

   ```bash
   gh pr checks
   ```

2. Select failing check URLs on the Nixbot host. Their normal shape is:

   ```text
   https://nixbot.tailb22a98.ts.net/repos/<FORGE>/<OWNER>/<REPO>/builds/<BUILD_NUMBER>
   ```

   Extract `FORGE`, `OWNER`, `REPO`, and `BUILD_NUMBER` from the URL. Do not guess a build number from branch or PR numbers.

3. Fetch the build summary through the repository's SecretSpec environment:

   ```bash
   secretspec run --reason "investigate Nixbot build" -- sh -c \
     'curl -sS -H "Authorization: Bearer $NIXBOT_API_KEY" "$1"' _ \
     "https://nixbot.tailb22a98.ts.net/api/repos/<FORGE>/<OWNER>/<REPO>/builds/<BUILD_NUMBER>"
   ```

   Inspect `build.status`, `build.error`, and the status/error of each entry in `attributes`.

4. Fetch the compact failure summary before downloading full logs:

   ```bash
   secretspec run --reason "investigate Nixbot failures" -- sh -c \
     'curl -sS -H "Authorization: Bearer $NIXBOT_API_KEY" "$1"' _ \
     "https://nixbot.tailb22a98.ts.net/api/repos/<FORGE>/<OWNER>/<REPO>/builds/<BUILD_NUMBER>/failures"
   ```

   Use each failed attribute's `error` and `log_tail` to identify the actionable cause.

5. Fetch a full attribute log only when the failure summary is insufficient:

   ```bash
   curl -sS \
     "https://nixbot.tailb22a98.ts.net/repos/<FORGE>/<OWNER>/<REPO>/builds/<BUILD_NUMBER>/logs/<ATTRIBUTE>"
   ```

   The response is HTML; opening the check or log URL in a browser may be more readable.

6. Group findings by check target and build number. Report only actionable failed attributes, distinguish primary failures from downstream/cancelled work, and include links back to the relevant checks.

## Guardrails and Fallbacks

- Access `NIXBOT_API_KEY` only through `secretspec run`. Never print, persist, or manually retrieve the key.
- If `secretspec` or the repo's `NIXBOT_API_KEY` declaration is unavailable, use the GitHub check details and public Nixbot pages, explain the limitation, and do not bypass secret management.
- If the API shape differs, fetch the live OpenAPI document and adapt to it.
- To confirm general service state, use the unauthenticated endpoints `GET /api/repos/<FORGE>/<OWNER>/<REPO>/builds?status=failed` and `GET /api/queue`.
- Treat a build that fails before attribute details appear as a likely prerequisite failure; verify before attributing downstream failures.
- Diagnose and report by default. Change code, rerun jobs, or mutate CI state only when the user requests it.

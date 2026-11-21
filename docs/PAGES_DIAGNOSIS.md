# Pages workflow: "Found 0 artifact(s)" diagnosis

Workflow: `.github/workflows/pages.yml` (site only; never builds or publishes an app package).

## Evidence (runs on gordasgdc/scaner-gdc, 2026-11-21)
- Runs 44953979827, 44954242612, 44955022985 failed in **attempt 1** at `actions/deploy-pages@v4` with
  `Found 0 artifact(s)` → `No artifacts named "github-pages" were found for this workflow run`.
  Runs 44954105507 and 44954417094 succeeded on attempt 1: 3 of 5 push runs failed (not deterministic).
- In the failing run the artifact exists: run 44955022985 lists `github-pages` (id 14726699396, created 22:07:00Z, not expired).
  Upload step ended 22:07:00Z and the deploy step listed artifacts at 22:07:00.40Z, i.e. within the same second.
  Upload and deploy were two steps of one job, so the listing ran immediately after the upload finalised.
- Permissions (`pages: write`, `id-token: write`), artifact name (`github-pages`), action versions (upload-pages-artifact@v3 → upload-artifact@v4, deploy-pages@v4) and concurrency (`group: pages`, no cancel) were correct and identical in succeeding and failing runs.
- "Multiple artifacts named github-pages … Artifact count is 2" (attempt 2 of 44955022985) is a consequence of "Re-run failed jobs": the whole job re-ran, uploaded a second artifact, and the first one still existed. It is a secondary symptom, not a second cause.
- A manual `workflow_dispatch` succeeding proves nothing by itself (it simply lost the race less often).

## Cause (as far as the evidence goes)
A race between artifact finalisation and its visibility in the artifacts listing API used by `deploy-pages`, triggered by upload and deploy sharing one job.
The listing is GitHub-side; the action does not retry it. This is an inference from timing + the artifact being present afterwards, not a statement from GitHub.

## Fix
Split into `build` (check + upload) and `deploy` (`needs: build`, only `deploy-pages`): the deploy job starts on a new runner after the upload job completes
(the layout of GitHub's own Pages starter workflow). A failed deploy can be re-run alone without a second artifact. No retry loop; a real failure stays red.

## Verification
See Results.

## Results
Push-triggered runs with the two-job layout (all attempt 1, no re-run, no manual dispatch):
- 44957688669 (push b7b32c5): build 5 s, deploy started 4 s later, success.
- 44958638096 (push 3b08d9b, workflow edit): success.
- 44958717660 (push 1887f04, workflow edit): success.
Before the change: 3 of 5 push runs failed on attempt 1. Three successes do not prove the race is gone (it was intermittent); the layout removes the same-second listing that caused it, and any remaining failure stays visible (no retry loop).

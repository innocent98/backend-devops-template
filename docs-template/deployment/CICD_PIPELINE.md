# CI/CD Pipeline — {{PROJECT_NAME}}

## The idea: build once, test that image, ship that image

The image is built **one time**, on `develop`. That exact image is deployed to staging and tested. Production later redeploys the **same image**, identified by its digest, and never builds anything. What you tested is what you ship.

```
PR → develop                 push to develop                         push to main
     │                            │                                       │
     ▼                            ▼                                       ▼
 ┌────────┐             ┌──────────────────┐                      ┌────────────────┐
 │  CI    │             │ CD (staging)     │                      │ CD (production)│
 │ lint   │             │ 1 build + push   │                      │ 1 find the     │
 │ test   │  merge      │   image (GHCR)   │   fast-forward       │   verified     │
 │ semgrep│ ───────▶    │ 2 deploy staging │   main to develop    │   image        │
 │ image  │             │ 3 live E2E       │ ──────────────────▶  │ 2 deploy it    │
 │ scan   │             │ 4 mark verified  │                      │   (no build)   │
 └────────┘             └──────────────────┘                      └────────────────┘
                                 image  ghcr.io/<owner>/<repo>@sha256:…  (same bytes)
```

## Files

| File | Runs on | Does |
|---|---|---|
| `ci.yml` | PR to `develop`; push to `develop` | Lint, tests, Semgrep. On PRs also builds the image (not pushed) and scans it with Trivy. `CI gate` is the single check to require. |
| `cd-staging.yml` | push to `develop`; manual | Build and push the image, deploy to staging, run live E2E, then mark the image verified. |
| `cd-production.yml` | push to `main`; manual (rollback) | Find the verified image for this commit and deploy it. |
| `registry-cleanup.yml` | weekly; manual (dry run by default) | Deletes old image versions from GHCR, keeping what a rollback needs. |
| `actions/deploy-stack` | called by both CD workflows | The shared deploy: decrypt env, ship, pull by digest, migrate, health check, roll back on failure. |
| `scripts/ghcr_digest.sh` | called by CD | Looks up an image's digest in GHCR. |

## How production knows an image was tested

After the live E2E passes, `cd-staging.yml` adds two tags to the tested image:

- `staging-verified-<full commit sha>` — "this commit passed staging". Used when `main` is pushed.
- `verified-sha256-<digest>` — "these exact bytes passed staging". Used for manual rollbacks.

`cd-production.yml` looks the tag up in the registry. No tag, no deploy. Only `cd-staging.yml` can add these tags, and only after E2E passes.

## Why `main` must be a fast-forward of `develop`

Production finds the image by the commit SHA. A fast-forward keeps the SHA unchanged; a squash or merge commit creates a new SHA that no image was built for. See `BRANCHING.md` for the exact commands and branch settings.

## Keeping images tidy

Two places hold images, and each has a cleanup:

| Where | Cleanup | Keeps |
|---|---|---|
| The VPS | `deploy-stack` runs `docker image prune -af --filter "until=72h"` after each successful deploy | The running image, plus unused images built in the last 72 hours (the filter counts from the image's build time, not when it was pulled). Rollback re-pulls from GHCR if needed. |
| GHCR | `registry-cleanup.yml` (weekly), using `scripts/ghcr_prune.sh` | 20 newest versions, 10 newest staging-verified versions, the tips of `main` and `develop`, anything under 14 days old. |

The limits are variables at the top of `ghcr_prune.sh` (`KEEP_NEWEST`, `KEEP_VERIFIED`, `MIN_AGE_DAYS`). Preview a cleanup first: **Actions → Registry cleanup → Run workflow** (dry run is ticked by default). A manual rollback can only target an image that still exists, so the last 10 verified images are your rollback window.

## Trust boundary: who can release

The "verified" tags are ordinary registry tags. The pipeline's safety rests on **who can run workflows with deploy secrets**, so:

- Set **Deployment branches** on both Environments (`GITHUB_ACTIONS_SETUP.md`, Step 2). This is the control that keeps other branches away from secrets.
- Treat repo write access as release power: anyone who can push workflow changes to `develop` can make an image look verified. Review changes to `.github/` like production code.
- If you need to defend against that, replace the tags with signed attestations (cosign or GitHub artifact attestations) that production checks against the `cd-staging.yml` identity. The template leaves that out to stay simple.

All actions are pinned to full commit SHAs. `.github/dependabot.yml` opens one weekly PR with the bumps; review it like any dependency update.

## CI cost controls

| Control | Effect |
|---|---|
| `main` is not a CI trigger | A commit arriving on `main` was already tested; it is not tested again. |
| Docs-only PRs skip lint, tests and the image scan | Semgrep still runs. |
| Draft PRs run nothing | Mark ready for review to run CI once. |
| Superseded PR runs are cancelled | Three quick pushes cost one run. |
| `CI gate` job | One check reports even when jobs are skipped, so branch protection stays simple. |

## Real HTTP tests

| Stage | What it runs | Real network? |
|---|---|---|
| CI `Tests` | `pytest tests/` (in-process `TestClient`) | No |
| CD `Live E2E` | `pytest tests/e2e -m e2e` against `$APP_URL` on the deployed staging stack | **Yes** |

Put server-dependent tests under `tests/e2e/` marked `@pytest.mark.e2e`, and skip them in `conftest.py` when `E2E_BASE_URL` is unset.

| Situation | Behavior |
|---|---|
| No `tests/e2e/` directory | Logged and skipped; the image is still marked verified. |
| `tests/e2e/` exists, no tests collected | pytest exit 5 is treated as success. |
| An E2E test fails | The job fails; the image is **not** verified and cannot reach production. |

## Deploy mechanics (`deploy-stack`)

1. Check every secret is set. 2. Decrypt `.env.<env>.enc` on the runner. 3. Ship `.env` and `docker-compose.prod.yml` to `$DEPLOY_PATH`. 4. On the VPS: record the running image, log in to GHCR with the run's own short-lived token, pull the image **by digest**, pin `API_IMAGE` in `.env`. 5. Run `alembic upgrade head` and the optional `scripts/seed_data.py`. 6. `docker compose up -d`, then poll `{{HEALTH_PATH}}`. If any step fails, the previous image is restored.

Production also installs the daily backup cron (`scripts/backup_cron.sh`).

No registry password is stored anywhere: the token is created for each run and expires when it ends.

## Optional: companion frontend E2E

If a frontend repo has its own E2E suite, add a job to `cd-staging.yml` after `staging-deploy` that dispatches the frontend workflow against `$APP_URL` and polls for its result, and add it to the `needs:` of `mark-verified`. It is left out to keep the template simple.

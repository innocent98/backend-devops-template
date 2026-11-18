# SOP: Build-once, promote-by-digest pipeline

**Date:** 2026-11-18 · **Status:** written and statically verified; not yet run on a real repo and VPS (see Verification) · **Commit:** 367729a (pushed to `main`)

## What shipped

The template's CI/CD was replaced with a build-once model: `develop` builds one image, staging tests it, `main` redeploys the same image to production without rebuilding. Release is a fast-forward of `main` to `develop`.

## Why

The old template rebuilt the image in the staging job and again in the production job, copied it with `scp`, and also built a third image in `docker.yml` and a fourth in CI. Production therefore ran bytes nobody had tested, and there was no rollback. A survey of Luran, Haven, Timpbills, Workchop and Cofoundaz found only Cofoundaz-api promoted the tested image. Luran and Haven pull a moving `:develop` tag (can drift from what staging tested); Timpbills builds twice and pushes mutable `:latest`/`:production` tags; Workchop has no CD.

## How

| Decision | Choice | Rejected alternative |
|---|---|---|
| Image identity | Deploy by **digest** (`ghcr.io/owner/repo@sha256:…`) | Moving tags (`:develop`, `:latest`): can point at different bytes later |
| Proof of staging test | Registry tag `staging-verified-<sha>` added only after live E2E passes; `verified-sha256-<hex>` for rollbacks | A shared `needs:` edge (impossible once staging and production are separate runs) |
| Release | Fast-forward `main` to `develop`; `main` requires linear history | Merge-agnostic lookup of `:develop` (Haven/Luran): simpler but can ship an untested image |
| Registry login on the VPS | The run's own short-lived `GITHUB_TOKEN` | A long-lived PAT stored as a secret |
| Deploy logic | One composite action used by both environments | Two copy-pasted blocks (drift risk) |
| Rollback | Auto-restore of the previous image on a failed deploy; manual redeploy of a verified tag | `docker tag … :latest` on the VPS |
| CI cost | No CI on `main`; docs-only and draft PRs skip; superseded PR runs cancel; one `CI gate` check | Running the full suite on every push and PR |
| Left out on purpose | SBOM, SLSA provenance, cosign signing, test sharding, pinned SHAs for first-party actions | Kept in Cofoundaz-api; they add length and jargon the template does not need. SSH/SCP actions are SHA-pinned because they hold the deploy key. |

Ideas kept from Cofoundaz-api: digest deploys, proof tags, composite deploy action, `ci-gate`, path filter, draft skipping, `ghcr_digest.sh` exit codes (0 found, 2 missing, 1 other). Behavior changes versus the old template: a missing `.env.<env>.enc` now fails the deploy (no "use the server's `.env`" mode); backup cron installs on production only; alembic must be baked into the image.

## What's involved

| Path | Change |
|---|---|
| `.github-template/workflows/ci.yml` | Rewritten: `changes`, `lint`, `test`, `security`, `image-check` (PR only, Trivy image scan), `ci-gate` |
| `.github-template/workflows/cd-staging.yml` | New: build, deploy, live E2E, mark verified, manual `image_tag` redeploy |
| `.github-template/workflows/cd-production.yml` | New: resolve verified image, deploy; manual `image_tag` rollback |
| `.github-template/actions/deploy-stack/action.yml` | New shared deploy |
| `.github-template/workflows/cd.yml`, `docker.yml` | Removed |
| `scripts/ghcr_digest.sh` | New (from Cofoundaz-api, made generic) |
| `install.sh` | Copies the new files, warns about leftover old `cd.yml`/`docker.yml`, new checklist |
| `docs-template/deployment/` | New `BRANCHING.md`, `ROLLBACK.md`; rewrote `CICD_PIPELINE.md`, `GITHUB_ACTIONS_SETUP.md`; fixed references elsewhere |
| `README.md` | New model, file list, assumptions, migration note |

Config an adopting project needs: secrets `VPS_HOST`, `VPS_USERNAME`, `VPS_SSH_KEY`, `DEPLOY_PATH`, `ENV_ENCRYPTION_KEY` (and optional `VPS_SSH_PASSPHRASE`) per environment; variables `APP_URL`, optional `VPS_PORT`; repo secret `CI_SECRET_KEY`; branch rules (`main` linear history, `develop` PR + `CI gate`).

## Verification

| Check | Result |
|---|---|
| `actionlint` on installed `ci.yml`, `cd-staging.yml`, `cd-production.yml` | clean |
| `shellcheck` on `ghcr_digest.sh` and every `run`/`script` block of `deploy-stack` | clean |
| `install.sh` into a scratch repo (with a stale old `docker.yml` present) | exit 0, no leftover `{{PLACEHOLDER}}`, stale-file warning printed. Found and fixed a crash on `${API_IMAGE}` in the checklist text. |
| `env.sh encrypt` then `deploy-stack` decrypt step; wrong key | round trip returns the same variables; wrong key fails with a clear error |
| `ghcr_digest.sh` against a public GHCR image | existing tag returns a digest (rc 0); missing tag returns rc 2 |
| **Not verified live:** the `imagetools create` retag keeping the same digest, the VPS deploy/rollback script, GHCR pull with `GITHUB_TOKEN`, E2E job | These need a real repo, GHCR package and VPS. The workflow asserts the digest match at mint time, so a retag problem fails loudly. First adoption (suggest a low-risk project) is the live test. |

## Operate / roll back

Install: `./install.sh --target <repo> --name "…" --slug …`. Migrating an existing project: see README "Moving a project off the old template". To revert this change in the template: `git revert` the commit; installed projects keep whatever they copied.

## Follow-ups

- Run it live on one project and record real captures; fix anything the first run shows.
- Decide whether to template a `dependabot.yml` for action version bumps, and whether to SHA-pin first-party actions.
- Optional modules left out: companion-frontend E2E dispatch, test sharding, SBOM/provenance.
- Haven, Luran and Timpbills could adopt this later (Timpbills first: it builds twice and uses mutable tags).

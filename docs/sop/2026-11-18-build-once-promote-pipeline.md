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
| Action pinning | Every action pinned to a full commit SHA (version in a comment); weekly `dependabot.yml` PR bumps them | Mutable tags: a tag can be repointed (the trivy-action incident) |
| Who can reach deploy secrets | Environment "Deployment branches" (`staging` → develop, `production` → main), documented as required; `github.ref` checks in the workflows only stop accidental runs | `if: github.ref` alone: a branch edits its own copy of the workflow, so it is not a control |
| Left out on purpose | SBOM, SLSA provenance, cosign/attestation signing, test sharding | Kept in Cofoundaz-api; they add length and jargon the template does not need. Consequence: the "verified" tags are plain registry tags, so anyone who can push workflows to the repo can mint one. Documented as the trust boundary in `CICD_PIPELINE.md`. |

Ideas kept from Cofoundaz-api: digest deploys, proof tags, composite deploy action, `ci-gate`, path filter, draft skipping, `ghcr_digest.sh` exit codes (0 found, 2 missing, 1 other). Behavior changes versus the old template: a missing `.env.<env>.enc` now fails the deploy (no "use the server's `.env`" mode); backup cron installs on production only; alembic must be baked into the image.

## What's involved

| Path | Change |
|---|---|
| `.github-template/workflows/ci.yml` | Rewritten: `changes`, `lint`, `test`, `security`, `image-check` (PR only, Trivy image scan), `ci-gate` |
| `.github-template/workflows/cd-staging.yml` | New: build, deploy, live E2E, mark verified, manual `image_tag` redeploy |
| `.github-template/workflows/cd-production.yml` | New: resolve verified image, deploy; manual `image_tag` rollback |
| `.github-template/actions/deploy-stack/action.yml` | New shared deploy |
| `.github-template/workflows/registry-cleanup.yml`, `scripts/ghcr_prune.sh` | Added 2026-11-21: weekly GHCR retention (keeps 20 newest, 10 newest verified, tips of main/develop, anything under 14 days); manual runs dry-run by default |
| `.github-template/dependabot.yml` | New: weekly bump PR for pinned actions (installed to `.github/dependabot.yml`) |
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
| `ghcr_prune.sh` retention rules, against a 40-version fixture with a stubbed `gh` | selected exactly the expected 15 versions; dry run made no delete calls; real run made 15; bad input rejected |
| **Not verified live:** the `imagetools create` retag keeping the same digest, the GHCR list/delete API calls and whether `GITHUB_TOKEN` is allowed to delete package versions (it may need the repo's Admin role on the package), the VPS deploy/rollback script, GHCR pull with `GITHUB_TOKEN`, E2E job | These need a real repo, GHCR package and VPS. The workflow asserts the digest match at mint time, so a retag problem fails loudly. First adoption (suggest a low-risk project) is the live test. |

## Security review follow-up (2026-11-18, same day)

An automated review of the first push found four issues; all handled in the follow-up commit:

| Finding | Resolution |
|---|---|
| Docs-only path filter bypass: a code file renamed into `docs/` looked docs-only | `ci.yml` now also checks `previous_filename` |
| `workflow_dispatch` runnable from any branch | Branch guards added; Environment deployment-branch rules documented as required in setup docs, `BRANCHING.md` and the installer checklist |
| Proof tag forgeable by anyone with `packages: write` | Accepted trade-off, documented trust boundary; attestations are the upgrade path |
| Unpinned actions | All pinned to SHAs, plus `dependabot.yml`. Also fixed a real bug: `trivy-action@0.28.0` is not a tag that exists (it is `v0.28.0`); now pinned to the reviewed v0.36.0 commit used by Cofoundaz-api |

## Operate / roll back

Install: `./install.sh --target <repo> --name "…" --slug …`. Migrating an existing project: see README "Moving a project off the old template". To revert this change in the template: `git revert` the commit; installed projects keep whatever they copied.

## Follow-ups

- Run it live on one project and record real captures; fix anything the first run shows.
- Optional modules left out: companion-frontend E2E dispatch, test sharding, SBOM/provenance.
- Haven, Luran and Timpbills could adopt this later (Timpbills first: it builds twice and uses mutable tags).

# backend-devops-template: build checklist

Snapshot (2026-11-18): 1 module done and statically verified, 1 module awaiting its first live run, 2 planned.

Legend: `[x]` done and verified · `[ ]` not done · "(static)" = linted and install-tested but not yet run on a real repo and VPS.

## Module 1: Build-once promote-by-digest pipeline (static)

- [x] Survey Luran, Haven, Timpbills, Workchop, Cofoundaz CI/CD; pick the model (2026-11-18)
- [x] `ci.yml`: path filter, draft skip, cancel superseded, `CI gate`, PR-only image scan
- [x] `cd-staging.yml`: build once, deploy by digest, live E2E, mark verified, manual redeploy
- [x] `cd-production.yml`: resolve verified image, deploy, manual rollback, no build
- [x] `actions/deploy-stack`: decrypt env, SSH deploy, health check, auto-rollback
- [x] `scripts/ghcr_digest.sh` (tested against public GHCR)
- [x] `install.sh` updated and install-tested
- [x] Docs: `BRANCHING.md`, `ROLLBACK.md`, `CICD_PIPELINE.md`, `GITHUB_ACTIONS_SETUP.md`, README
- [x] SOP: `docs/sop/2026-11-18-build-once-promote-pipeline.md`
- [x] Commit and push to `origin` (367729a, 2026-11-18)
- [x] Security review follow-up: rename bypass fixed, actions SHA-pinned, `dependabot.yml`, branch guards, Environment deployment-branch rules documented (2026-11-18)
- [ ] First live run on a real project; confirm retag digest match, VPS deploy, rollback

## Module 2: Adopt in existing projects

- [ ] Timpbills (builds twice, mutable tags)
- [ ] Haven, Luran (move off the moving `:develop` tag)
- [ ] Cofoundaz-api (already on the model; compare and fold back any improvements)

## Backlog

- [ ] Optional: test sharding module, SBOM/provenance module
- [ ] Optional: companion-frontend E2E dispatch module

## Deferred follow-ups

- Signed attestations for the verified proof (replaces plain registry tags) if repo write access ever needs to be less trusted
- Template a `docker-compose.prod.yml` and Dockerfile snippet that satisfy the pipeline's assumptions

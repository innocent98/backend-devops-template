# backend-devops-template

GitHub Actions workflows, docs, and scripts for Python/FastAPI backends deployed to a Docker-Compose VPS. One command installs it into any backend repo.

**The model: build once, test that image, ship that image.** `develop` builds the image one time and tests it on staging. `main` redeploys that exact image (by digest) to production, with no rebuild. Release = fast-forward `main` to `develop`. See [CICD_PIPELINE.md](docs-template/deployment/CICD_PIPELINE.md).

## Install into a project

```bash
/path/to/backend-devops-template/install.sh \
  --target /path/to/your/backend \
  --name "Your API" \
  --slug your-slug
```

`--slug` is your project's base name (e.g., `weysure`, `haven`). The template appends `-api`, so image name becomes `weysure-api`, `haven-api`, etc. Pass the identity only.

Optional flags (all have defaults):

| Flag | Default |
|---|---|
| `--deploy-path` | `/opt/<slug>` |
| `--health-path` | `/api/v1/health` |
| `--api-port` | `8000` |
| `--py-version` | `3.11` |
| `--poetry-version` | `1.8.4` |
| `--force` | off — overwrites existing files |

Existing files are **skipped** by default (safe to re-run). Use `--force` to overwrite.

## What lands in your repo

```
.github/workflows/
  ci.yml             # PRs + develop: lint, test, Semgrep; PRs also image build + Trivy scan
  cd-staging.yml     # push develop: build once → GHCR → deploy staging → live E2E → mark verified
  cd-production.yml  # push main: deploy the verified image (never builds); manual run = rollback
  registry-cleanup.yml  # weekly: prune old GHCR images, keep the rollback window (dry run by default when manual)
.github/actions/
  deploy-stack/      # shared deploy: decrypt env, pull by digest, migrate, health check, auto-rollback
.github/dependabot.yml   # weekly PR to bump the SHA-pinned actions

docs/deployment/
  GITHUB_ACTIONS_SETUP.md   # secrets + SSH key walkthrough
  CICD_PIPELINE.md          # what each stage does
  BRANCHING.md              # how to release (fast-forward main)
  ROLLBACK.md               # automatic + manual rollback
  DEPLOYMENT_GUIDE.md       # VPS + Compose + nginx + SSL
  PREDEPLOY_GUIDE.md        # local checks before pushing
  ENV_ENCRYPTION.md         # .env encryption pattern
  BACKUPS_GUIDE.md          # backup + restore + cloud providers

scripts/
  env.sh              # encrypt/decrypt/verify/rotate/diff/generate-key
  backup_db.sh        # dev-facing manual backup
  backup_cron.sh      # cron-safe production backup (auto-installed by the production deploy)
  ghcr_digest.sh      # looks up an image digest in GHCR (used by CD)
  ghcr_prune.sh       # GHCR retention rules (used by registry-cleanup.yml)
  backup_status.sh    # backup health check
  restore_db.sh       # restore with pre-restore safety snapshot
  security-scan.sh    # Semgrep SAST gate (run locally or in CI)
```

Nothing else in your repo is touched.

## After install

The installer prints a checklist. In short:

1. Generate an SSH keypair for GitHub Actions → VPS: `ssh-keygen -t ed25519 -f ~/.ssh/<slug>_deploy`
2. Add it to the VPS: `ssh-copy-id ...`
3. Create GitHub Environments `staging` and `production`, add the secrets and variables listed in `docs/deployment/GITHUB_ACTIONS_SETUP.md`.
4. Generate an encryption key: `./scripts/env.sh generate-key`
5. Encrypt your envs: `./scripts/env.sh encrypt staging && ./scripts/env.sh encrypt production`
6. Branch settings: `main` requires **linear history**; `develop` requires a PR and the **CI gate** check. Set each Environment's **Deployment branches** (`staging` → `develop`, `production` → `main`).
7. Merge to `develop` — staging builds, deploys and tests the image. Then `git push origin origin/develop:main` — production deploys that same image.

## What the template assumes

- Python with Poetry (`pyproject.toml` + `poetry.lock`).
- `app/` as the source dir (ruff + black target it).
- `tests/` with pytest. Optional `tests/e2e/` with `@pytest.mark.e2e`.
- `Dockerfile` at repo root. It must copy `alembic/` and `alembic.ini` into the image (the VPS pulls the image, not the source).
- `docker-compose.prod.yml` at repo root, with an `api` service using `image: ${API_IMAGE}`.
- A health endpoint (`--health-path`, default `/api/v1/health`).
- Optional `scripts/seed_data.py` in the image — runs after migrations if present.
- Encrypted env files `.env.staging.enc` and `.env.production.enc` committed (a deploy fails without them).

The optional pieces (E2E suite, seed script, `security-scan.sh`) are skipped if absent. The encrypted env files and the compose/Dockerfile requirements above are not optional.

## Moving a project off the old template

The old template had `cd.yml` (rebuilt the image in both staging and production, copied it with scp) and `docker.yml`. Delete both, run the installer with `--force`, add the new secrets/variables, set the branch rules, and make sure the Dockerfile bakes in alembic. The first merge to `develop` then builds the first verified image; fast-forward `main` to it to go live.

## Updating an installed project

Re-run `install.sh --force` to pull the latest template. `git diff` shows what changed. Keep your local customizations by leaving `--force` off for the files you've modified.

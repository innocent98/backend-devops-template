# backend-devops-template

GitHub Actions workflows, docs, and scripts for Python/FastAPI backends deployed to a Docker-Compose VPS. One command installs it into any backend repo.

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
  ci.yml          # lint + test + Semgrep SAST + build + Trivy CVE scan
  cd.yml          # staging deploy → API E2E → production deploy
  docker.yml      # GHCR build+push

docs/deployment/
  GITHUB_ACTIONS_SETUP.md   # secrets + SSH key walkthrough
  CICD_PIPELINE.md          # what each stage does
  DEPLOYMENT_GUIDE.md       # VPS + Compose + nginx + SSL
  PREDEPLOY_GUIDE.md        # local checks before pushing
  ENV_ENCRYPTION.md         # .env encryption pattern
  BACKUPS_GUIDE.md          # backup + restore + cloud providers

scripts/
  env.sh              # encrypt/decrypt/verify/rotate/diff/generate-key
  backup_db.sh        # dev-facing manual backup
  backup_cron.sh      # cron-safe production backup (auto-installed by CD)
  backup_status.sh    # backup health check
  restore_db.sh       # restore with pre-restore safety snapshot
  security-scan.sh    # Semgrep SAST gate (run locally or in CI)
```

Nothing else in your repo is touched.

## After install

The installer prints a checklist. In short:

1. Generate an SSH keypair for GitHub Actions → VPS: `ssh-keygen -t ed25519 -f ~/.ssh/<slug>_deploy`
2. Add it to the VPS: `ssh-copy-id ...`
3. Create GitHub Environments `staging` and `production`, add the secrets listed in `docs/deployment/GITHUB_ACTIONS_SETUP.md`.
4. Generate an encryption key: `./scripts/env.sh generate-key`
5. Encrypt your envs: `./scripts/env.sh encrypt staging && ./scripts/env.sh encrypt production`
6. Push to `main` — CI runs, staging deploys, E2E runs, production deploys if E2E passes.

## What the template assumes

- Python with Poetry (`pyproject.toml` + `poetry.lock`).
- `app/` as the source dir (ruff + black target it).
- `tests/` with pytest. Optional `tests/e2e/` with `@pytest.mark.e2e`.
- `Dockerfile` at repo root.
- `docker-compose.prod.yml` at repo root.
- Alembic at `alembic/`.
- Optional `scripts/seed_data.py` — runs after migrations if present.

If any optional piece is missing, the workflow just skips that step — nothing breaks.

## Updating an installed project

Re-run `install.sh --force` to pull the latest template. `git diff` shows what changed. Keep your local customizations by leaving `--force` off for the files you've modified.

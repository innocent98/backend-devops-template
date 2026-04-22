# backend-devops-template

Opinionated, reusable GitHub Actions + documentation bundle for Python/FastAPI backends deployed to a Docker-Compose VPS. Forked from the Luran pipeline and stripped to a generic core.

## What's in the box

```
.github-template/workflows/
  ci.yml          # lint (ruff + black) → test (pytest + Postgres + Redis + coverage)
                  # → build Docker image → Trivy SAST
  cd.yml          # staging-deploy → staging-api-e2e → production-deploy (gated)
  docker.yml      # GHCR build+push, tagged by branch/PR/SHA/semver

docs-template/deployment/
  GITHUB_ACTIONS_SETUP.md   # Secrets + SSH key walkthrough (10-minute setup)
  CICD_PIPELINE.md          # Visual pipeline + why each stage exists
  DEPLOYMENT_GUIDE.md       # VPS + Compose + nginx + SSL + backup guide
  PREDEPLOY_GUIDE.md        # Local verification before pushing to main
  ENV_ENCRYPTION.md         # openssl AES-256 + PBKDF2 pattern for .env.<env>

scripts/
  encrypt-env.sh  # Helper: plaintext .env → committed .env.<env>.enc

install.sh        # One command: copy + parameterize into a target repo
```

## One-command install

From the template directory:

```bash
./install.sh \
  --target /path/to/your/backend \
  --name "Your API" \
  --slug your-api
```

Full options:

```bash
./install.sh \
  --target /path/to/your/backend \
  --name "Your API" \
  --slug your-api \
  --deploy-path /opt/your-api \
  --health-path /api/v1/health \
  --api-port 8000 \
  --py-version 3.11 \
  --poetry-version 1.8.4
```

Flags:

| Flag | Default | Purpose |
|---|---|---|
| `--target` | _required_ | Target repo root |
| `--name` | _required_ | Human-readable project name |
| `--slug` | _required_ | `lower-kebab` — used as the base of the image name (`<slug>-api`) and concurrency groups. Pass the project identity only; the template appends `-api`. E.g., for a project called "Weysure API" use `--slug weysure`, which yields image `weysure-api`. Passing `--slug weysure-api` would give `weysure-api-api`. |
| `--deploy-path` | `/opt/<slug>` | Where the production stack lives on the VPS |
| `--health-path` | `/api/v1/health` | HTTP path CD polls after deploy |
| `--api-port` | `8000` | Port the container exposes on the VPS |
| `--py-version` | `3.11` | Python version for CI |
| `--poetry-version` | `1.8.4` | Poetry version for CI |
| `--force` | _off_ | Overwrite files that already exist in the target |

Running the installer copies nine files into your target repo and substitutes the `{{TOKEN}}` placeholders throughout. It prints a post-install checklist of the GitHub secrets to configure.

## What the template assumes about your project

- **Python** with **Poetry** (`pyproject.toml` + `poetry.lock`).
- `app/` as the source directory (ruff and black target `app/`).
- `tests/` with pytest. Optional `tests/e2e/` with `@pytest.mark.e2e` for live HTTP tests.
- A `Dockerfile` at the repo root.
- A `docker-compose.prod.yml` at the repo root.
- Alembic at `alembic/` with `alembic.ini`.
- Optional `scripts/seed_data.py` — called after migrations if present.
- Optional `scripts/backup_cron.sh` — installed as a daily cron if present.

None of these are hard-required; the CD workflow degrades gracefully for the optional ones.

## What's stripped from the Luran original

| Removed | Why | How to add back |
|---|---|---|
| Multi-phase encryption migrations | Luran-specific rollout; `alembic upgrade head` is enough for most projects. | See `PREDEPLOY_GUIDE.md` for the two-phase migration pattern. |
| Cross-repo dashboard E2E dispatch | Needs a separate frontend repo and token. | See `CICD_PIPELINE.md` — "Adding cross-repo coordination". |
| `automation-flow-regression` job | Domain-specific pytest paths. | Add as a new CI job if relevant. |
| Inline `OPENAI_API_KEY`, `PAYSTACK_SECRET_KEY` in CI YAML | Bad habit — even dummy values should come from secrets. | Put them in repo secrets and reference with `${{ secrets.X }}`. |

## Keeping your copy in sync with upstream

The template intentionally ships as a **copy**, not a submodule. You own the workflows after install and can modify them freely. When the template updates, run `install.sh` with `--force` to overwrite — review the diff with `git diff` before committing.

If you've customized a workflow file and don't want to lose your changes, skip `--force` for that file and merge by hand.

## Design principles

1. **Fail before staging, not on it.** CI runs the full test suite. Staging only hosts tests that need real network.
2. **Staging is a gate, not a deploy target.** Production only deploys when staging E2E passes.
3. **Every deploy is immutable.** Images are SHA-tagged, shipped as `.tar.gz`, `docker load`ed on the VPS. Rollback = re-tag the previous SHA.
4. **Secrets never touch git.** Env files are AES-encrypted before commit; CI keys live in GitHub secrets.
5. **Least privilege.** CD workflow declares `permissions: contents: read`. The template doesn't request write permissions unless a step actually needs them.

## Credits

Based on the production CI/CD pipeline used in `luran/luran`. The Luran pipeline in turn borrows standard patterns from GitHub Actions docs, `docker/build-push-action`, and `appleboy/ssh-action`.

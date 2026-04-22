#!/usr/bin/env bash
# install.sh — copy parameterized DevOps template into a target backend project.
#
# Usage:
#   ./install.sh --target <path> --name "Project Name" --slug project-slug \
#                [--deploy-path /opt/project-slug] \
#                [--health-path /api/v1/health] \
#                [--api-port 8000] \
#                [--py-version 3.11] \
#                [--poetry-version 1.8.4] \
#                [--force]
#
# What it does:
#   1. Copies .github-template/workflows/ → <target>/.github/workflows/
#   2. Copies docs-template/deployment/   → <target>/docs/deployment/
#   3. Copies scripts/encrypt-env.sh      → <target>/scripts/encrypt-env.sh
#   4. Substitutes {{TOKEN}} placeholders across the copied files.
#   5. Prints a post-install checklist (secrets to add, SSH key to generate).

set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Defaults --------------------------------------------------------------
TARGET=""
PROJECT_NAME=""
PROJECT_SLUG=""
DEPLOY_PATH=""
HEALTH_PATH="/api/v1/health"
API_PORT="8000"
PY_VERSION="3.11"
POETRY_VERSION="1.8.4"
FORCE=0

usage() {
  sed -n '2,18p' "$0"
  exit "${1:-0}"
}

# --- Arg parse -------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --target)          TARGET="$2"; shift 2 ;;
    --name)            PROJECT_NAME="$2"; shift 2 ;;
    --slug)            PROJECT_SLUG="$2"; shift 2 ;;
    --deploy-path)     DEPLOY_PATH="$2"; shift 2 ;;
    --health-path)     HEALTH_PATH="$2"; shift 2 ;;
    --api-port)        API_PORT="$2"; shift 2 ;;
    --py-version)      PY_VERSION="$2"; shift 2 ;;
    --poetry-version)  POETRY_VERSION="$2"; shift 2 ;;
    --force)           FORCE=1; shift ;;
    -h|--help)         usage 0 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

# --- Validate --------------------------------------------------------------
[ -n "$TARGET" ]       || { echo "ERROR: --target is required." >&2; exit 1; }
[ -n "$PROJECT_NAME" ] || { echo "ERROR: --name is required." >&2; exit 1; }
[ -n "$PROJECT_SLUG" ] || { echo "ERROR: --slug is required." >&2; exit 1; }

if ! [[ "$PROJECT_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: --slug must be lowercase alphanumerics and dashes (got: $PROJECT_SLUG)" >&2
  exit 1
fi

# Slug is also used as a Docker image tag component — it's already constrained above.
[ -d "$TARGET" ] || { echo "ERROR: target directory does not exist: $TARGET" >&2; exit 1; }

if [ -z "$DEPLOY_PATH" ]; then
  DEPLOY_PATH="/opt/${PROJECT_SLUG}"
fi

echo "Installing DevOps template into: $TARGET"
echo "  Project name:     $PROJECT_NAME"
echo "  Project slug:     $PROJECT_SLUG"
echo "  Deploy path:      $DEPLOY_PATH"
echo "  Health endpoint:  $HEALTH_PATH"
echo "  API port:         $API_PORT"
echo "  Python version:   $PY_VERSION"
echo "  Poetry version:   $POETRY_VERSION"
echo ""

# --- Helpers ---------------------------------------------------------------
substitute() {
  # Replace {{TOKEN}} placeholders in a single file, in place.
  # Uses a dedicated sed invocation per token so no token's value can be
  # accidentally treated as a regex metacharacter by a later substitution.
  local file="$1"
  local tmp; tmp="$(mktemp)"
  cp "$file" "$tmp"
  python3 - "$tmp" <<'PY'
import sys, pathlib, os
path = pathlib.Path(sys.argv[1])
text = path.read_text()
subs = {
    "{{PROJECT_NAME}}":   os.environ["PROJECT_NAME"],
    "{{PROJECT_SLUG}}":   os.environ["PROJECT_SLUG"],
    "{{DEPLOY_PATH}}":    os.environ["DEPLOY_PATH"],
    "{{HEALTH_PATH}}":    os.environ["HEALTH_PATH"],
    "{{API_PORT}}":       os.environ["API_PORT"],
    "{{PY_VERSION}}":     os.environ["PY_VERSION"],
    "{{POETRY_VERSION}}": os.environ["POETRY_VERSION"],
}
for tok, val in subs.items():
    text = text.replace(tok, val)
path.write_text(text)
PY
  mv "$tmp" "$file"
}

copy_with_overwrite_check() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && [ "$FORCE" -ne 1 ]; then
    echo "  SKIP (exists, use --force to overwrite): $dst"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "  wrote: $dst"
}

export PROJECT_NAME PROJECT_SLUG DEPLOY_PATH HEALTH_PATH API_PORT PY_VERSION POETRY_VERSION

# --- Copy files ------------------------------------------------------------
echo "Copying workflows…"
for wf in ci.yml cd.yml docker.yml; do
  src="$TEMPLATE_DIR/.github-template/workflows/$wf"
  dst="$TARGET/.github/workflows/$wf"
  copy_with_overwrite_check "$src" "$dst"
  [ -f "$dst" ] && substitute "$dst"
done

echo "Copying deployment docs…"
for doc in DEPLOYMENT_GUIDE.md GITHUB_ACTIONS_SETUP.md CICD_PIPELINE.md PREDEPLOY_GUIDE.md ENV_ENCRYPTION.md BACKUPS_GUIDE.md; do
  src="$TEMPLATE_DIR/docs-template/deployment/$doc"
  dst="$TARGET/docs/deployment/$doc"
  [ -f "$src" ] || { echo "  SKIP (missing in template): $doc"; continue; }
  copy_with_overwrite_check "$src" "$dst"
  [ -f "$dst" ] && substitute "$dst"
done

echo "Copying scripts…"
shopt -s nullglob
for src in "$TEMPLATE_DIR/scripts/"*.sh; do
  sh="$(basename "$src")"
  dst="$TARGET/scripts/$sh"
  copy_with_overwrite_check "$src" "$dst"
  if [ -f "$dst" ]; then
    substitute "$dst"
    chmod +x "$dst"
  fi
done
shopt -u nullglob

# --- Post-install checklist -----------------------------------------------
cat <<EOF

================================================================================
Install complete.

Next steps (one-time per project):

1. Generate an SSH keypair for GitHub Actions → your VPS:
     ssh-keygen -t ed25519 -f ~/.ssh/${PROJECT_SLUG}_deploy -C "gha-${PROJECT_SLUG}"
     ssh-copy-id -i ~/.ssh/${PROJECT_SLUG}_deploy.pub <user>@<vps-host>

2. On GitHub → Settings → Environments, create two environments: "staging" and
   "production". Add these secrets to each (values differ per environment):

     VPS_HOST              # e.g., vps.example.com
     VPS_USERNAME          # e.g., deploy
     VPS_SSH_KEY           # contents of ~/.ssh/${PROJECT_SLUG}_deploy
     VPS_PORT              # 22 by default
     VPS_SSH_PASSPHRASE    # optional; leave unset if key has no passphrase
     DEPLOY_PATH           # staging: /opt/${PROJECT_SLUG}-staging
                           # production: /opt/${PROJECT_SLUG}
     APP_URL               # e.g., https://api.example.com${HEALTH_PATH%/*}
     API_PORT              # staging: 8001; production: ${API_PORT}
     ENV_ENCRYPTION_KEY    # the AES passphrase you used to encrypt .env.<env>.enc

3. Also add these repo-level secrets (shared across environments):

     CI_SECRET_KEY         # a 32+ char random string for test runs
     # Plus any CI_<SERVICE>_* secrets your tests need for third-party APIs.
     # Example: CI_STRIPE_API_KEY, CI_SUPABASE_JWT_SECRET. Reference them in
     # ci.yml under the "Run tests" step's env: block.

4. On your VPS, bootstrap the deployment directories:

     sudo mkdir -p /opt/${PROJECT_SLUG} /opt/${PROJECT_SLUG}-staging
     sudo chown \$USER:\$USER /opt/${PROJECT_SLUG} /opt/${PROJECT_SLUG}-staging
     # Create .env for each stack (or let CD decrypt .env.<env>.enc).

5. Generate an encryption key and encrypt your env files (run from the repo root):

     # One-time: generate a 32-byte hex key
     ./scripts/env.sh generate-key
     # Save the output to GitHub secrets AND to a local .env.key (gitignored)

     # Then encrypt each environment's .env:
     ./scripts/env.sh encrypt staging
     ./scripts/env.sh encrypt production

   Commit the .enc files, never the plaintext .env.<env> files.
   Other useful commands: decrypt, verify, rotate, diff. Run with no args
   for help:  ./scripts/env.sh

6. (Optional) Configure backups. The CD pipeline auto-installs a daily
   cron that calls scripts/backup_cron.sh. For cloud uploads:

     # Add to your .env.<env> (and re-encrypt):
     #   ENABLE_CLOUD_BACKUP=true
     #   CLOUD_PROVIDER=b2        # or: gdrive, dropbox, s3
     #   B2_BUCKET=${PROJECT_SLUG}-backups   # for CLOUD_PROVIDER=b2
     #   GDRIVE_FOLDER=${PROJECT_SLUG}-backups   # for CLOUD_PROVIDER=gdrive
     #   AWS_S3_BUCKET=${PROJECT_SLUG}-backups   # for CLOUD_PROVIDER=s3
     # Then install rclone (or awscli) on the VPS and run the provider's
     # one-time configuration. See BACKUPS_GUIDE.md for exact steps.

   See docs/deployment/BACKUPS_GUIDE.md for the full backup/restore flow.

7. Read docs/deployment/GITHUB_ACTIONS_SETUP.md for the full walkthrough,
   and docs/deployment/CICD_PIPELINE.md for what each stage does.

Done.
================================================================================
EOF

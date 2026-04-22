#!/usr/bin/env bash
# encrypt-env.sh — encrypt .env.<env> → .env.<env>.enc for safe VCS storage.
#
# Usage:
#   ENV_ENCRYPTION_KEY='<passphrase>' ./scripts/encrypt-env.sh <env>
#
# Example:
#   ENV_ENCRYPTION_KEY='correct-horse-battery-staple' ./scripts/encrypt-env.sh staging
#
# Symmetric AES-256-CBC with PBKDF2 key stretching (100k iterations).
# To decrypt manually:
#   openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
#     -in .env.staging.enc -out .env.staging -pass "pass:$ENV_ENCRYPTION_KEY"

set -euo pipefail

ENV_NAME="${1:-}"
[ -n "$ENV_NAME" ] || { echo "Usage: ENV_ENCRYPTION_KEY=... $0 <env-name>" >&2; exit 1; }
[ -n "${ENV_ENCRYPTION_KEY:-}" ] || { echo "ERROR: ENV_ENCRYPTION_KEY env var is required." >&2; exit 1; }

IN=".env.${ENV_NAME}"
OUT=".env.${ENV_NAME}.enc"

[ -f "$IN" ] || { echo "ERROR: $IN not found in $(pwd)" >&2; exit 1; }

openssl enc -aes-256-cbc -e -pbkdf2 -iter 100000 \
  -in "$IN" -out "$OUT" -pass "pass:$ENV_ENCRYPTION_KEY"

echo "Encrypted: $IN → $OUT"
echo "Commit $OUT. Do NOT commit $IN."

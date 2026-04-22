# Env Encryption — {{PROJECT_NAME}}

How we ship environment files to the VPS without leaking secrets to git.

## The pattern

1. Keep `.env.staging` and `.env.production` in `.gitignore` (plaintext — **never committed**).
2. Encrypt them to `.env.staging.enc` and `.env.production.enc` with AES-256-CBC + PBKDF2 (100k iterations).
3. Commit the `.enc` files.
4. Store the AES passphrase as the GitHub environment secret `ENV_ENCRYPTION_KEY` (different passphrase per environment is fine — each environment has its own secret).
5. CD decrypts on the runner, `scp`s the resulting `.env` to the VPS, then the file is deleted from the runner when the job ends.

This gives you:
- Environment config in version control (auditable, rollback-able).
- Secrets not visible to anyone who clones the repo.
- No manual env-editing on the VPS during deploy — CD handles it.

## Encrypt (one command)

From the repo root:

```bash
ENV_ENCRYPTION_KEY='<strong-passphrase>' ./scripts/encrypt-env.sh staging
ENV_ENCRYPTION_KEY='<strong-passphrase>' ./scripts/encrypt-env.sh production
```

That produces `.env.staging.enc` and `.env.production.enc`. Commit those, never the plaintext.

## Decrypt (for debugging)

```bash
openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
  -in .env.staging.enc \
  -out .env.staging \
  -pass "pass:$ENV_ENCRYPTION_KEY"
```

## `.gitignore` must contain

```
# Plaintext env files — never commit
.env
.env.local
.env.staging
.env.production
```

## Passphrase management

Generate a strong one:

```bash
openssl rand -base64 48
```

Store it in **exactly three** places:

1. Your password manager (so you can re-encrypt after editing `.env.<env>`).
2. GitHub → Settings → Environments → `staging` / `production` → secret `ENV_ENCRYPTION_KEY`.
3. Nowhere else. Not in Slack, not in email, not in a `passphrase.txt` file.

Rotating the passphrase:

```bash
# 1. Decrypt with the old passphrase
openssl enc -aes-256-cbc -d -pbkdf2 -iter 100000 \
  -in .env.staging.enc -out .env.staging \
  -pass "pass:$OLD_KEY"

# 2. Re-encrypt with the new passphrase
ENV_ENCRYPTION_KEY="$NEW_KEY" ./scripts/encrypt-env.sh staging

# 3. Update the GitHub secret, commit the new .enc, delete plaintext
git add .env.staging.enc
git commit -m "chore: rotate staging env encryption key"
rm .env.staging
```

## What if CD has no key and no `.enc` file?

The CD workflow's decrypt step is tolerant — it logs a warning and moves on. In that case, the VPS must already have a valid `.env` at `$DEPLOY_PATH/.env` (put there manually). Use this path if you're adopting encryption mid-project and haven't rolled it out yet.

## Why AES-256-CBC + PBKDF2 and not something fancier?

- It's in **every OpenSSL install on the planet** — zero dependencies on the runner and the VPS.
- PBKDF2 with 100k iterations is fine for passphrases with ≥64 bits of entropy (easy with `openssl rand -base64 48`).
- We're not trying to resist a state-level adversary with repo read access — we're trying to make `git clone` insufficient to recover the secrets. AES-256 does that.

If you want GPG or age instead, swap `encrypt-env.sh` and the decrypt step in `cd.yml`. The rest of the pipeline doesn't care how the `.env` comes into existence, as long as it ends up at `$DEPLOY_PATH/.env` on the VPS before `docker compose up`.

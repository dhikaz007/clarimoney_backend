# ClariMoney Backend

[![style: dart frog lint][dart_frog_lint_badge]][dart_frog_lint_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dart-frog.dev)

Dart Frog API for ClariMoney. Neon PostgreSQL backend.

## Local setup

```bash
cp .env.example .env
export DATABASE_URL='postgresql://...'
export JWT_SECRET='at-least-32-random-characters'
export ALLOWED_ORIGIN='http://localhost:3000'
export APP_BASE_URL='http://localhost:3000' # Frontend base URL for verification/reset links
# Optional email features: configure all SMTP values before sending mail.
export SMTP_HOST='smtp.gmail.com'
export SMTP_PORT='587'
export SMTP_USERNAME='you@gmail.com'
export SMTP_PASSWORD='google-app-password'
export SMTP_FROM='you@gmail.com'
dart pub get
dart_frog dev
```

Apply migrations before starting production:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/003_token_version.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_user_sessions.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/005_refresh_token_history.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/006_session_id_rotation.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/007_auth_tokens_email_verification.sql
```

## Verification

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
 JWT_SECRET="${JWT_SECRET:?export JWT_SECRET or load a shell-compatible .env}" dart test
dart_frog build
```

Production requirements:
- Rotate any Neon credential exposed outside secret storage.
- Set `DATABASE_URL`, `JWT_SECRET`, and `ALLOWED_ORIGIN` in deployment secrets.
- Set `APP_BASE_URL`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`,
  and `SMTP_FROM` to enable verification and password-reset email. Gmail requires
  2-Step Verification plus a Google App Password; use that App Password, never
  your normal Google password.
- Never commit `.env`.
- Access JWTs issued before this rollout lack required `sid` session binding and
  are invalid after deployment. Clients must sign in again.

Test policy:
- Run `JWT_SECRET="${JWT_SECRET:?export JWT_SECRET}" DATABASE_URL="${DATABASE_URL:?export DATABASE_URL}" dart test` for full Neon-backed verification. Load `.env` with a dotenv tool first; `.env` URLs may contain shell metacharacters.
- DB tests may skip only when `DATABASE_URL` or `JWT_SECRET` is absent in local development; release and CI runs must provide both and must not accept skipped DB tests.
- Migration 006 must run after 004 and 005. It replaces the history foreign key
  so same-device session UUID replacement cascades to `refresh_token_history`.
- Migrations assume clean ordered application. Existing objects are not repaired
  beyond explicit `IF NOT EXISTS`/named-constraint handling; inspect schema before
  applying to partially migrated databases.

## Render Free deployment

1. Push this repository to GitHub.
2. In Render, create a Blueprint from the repository.
3. Render reads `render.yaml` and builds `Dockerfile`.
4. Set `DATABASE_URL` to Neon connection string.
5. Set `ALLOWED_ORIGIN` to the allowed client origin.
6. Apply migrations against Neon before first deploy.

Render Free sleeps after inactivity. First request after sleep has cold-start delay.
Neon remains the persistent database; Render filesystem is ephemeral.

[dart_frog_lint_badge]: https://img.shields.io/badge/style-dart_frog_lint-1DF9D2.svg
[dart_frog_lint_link]: https://pub.dev/packages/dart_frog_lint
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT

# Database migrations

Run SQL files in numeric order against Neon before deploying backend changes.

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/003_token_version.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_user_sessions.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/005_refresh_token_history.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/006_session_id_rotation.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/007_auth_tokens_email_verification.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/008_drop_redundant_auth_token_hash_index.sql
```

Production uses `DATABASE_URL`; never commit credentials.

Migration 007 must run after migration 006 and before deploying email
verification, password reset, or account deletion routes. It adds optional
email verification state plus one-time hashed auth tokens. Apply migrations in
numeric order against each Neon database; inspect partially migrated databases
before retrying.

Migration 008 must run after migration 007. It safely removes the redundant
`idx_auth_tokens_hash` index from databases where migration 007 created it;
the unique constraint on `auth_tokens.token_hash` preserves required lookup
indexing. `DROP INDEX IF EXISTS` makes it safe for databases already corrected.

## Release environment

Set these variables in the runtime environment. Keep values out of Git,
Bruno environments, logs, and error responses:

- `DATABASE_URL` — Neon PostgreSQL connection string.
- `JWT_SECRET` — access-token signing secret.
- `APP_BASE_URL` — frontend base URL serving `/verify-email` and `/reset-password`; not API base unless frontend routes live there.
- `SMTP_HOST` — Gmail SMTP host, normally `smtp.gmail.com`.
- `SMTP_PORT` — SMTP port, normally `587`.
- `SMTP_USERNAME` — Gmail account address.
- `SMTP_PASSWORD` — Gmail App Password, not the normal Google password.
- `SMTP_FROM` — sender address permitted by that Gmail account.

Gmail delivery requires 2-Step Verification plus a Google App Password. Create
one under Google Account security, store it only in the deployment secret
manager, and revoke it when no longer needed. Missing SMTP configuration keeps
verification resend controlled; forgot-password responses remain generic.

Migration 006 is rerunnable. It recreates named foreign keys after migration
004/005: `refresh_token_history.session_id` uses `ON UPDATE CASCADE` because
same-device login replaces `user_sessions.id`; user deletion remains cascading.

Migrations assume clean numeric-order application. Existing incompatible tables
are not generally repaired. Inspect partially migrated databases before running.

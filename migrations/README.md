# Database migrations

Run SQL files in numeric order against Neon before deploying backend changes.

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/003_token_version.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_user_sessions.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/005_refresh_token_history.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/006_session_id_rotation.sql
```

Production uses `DATABASE_URL`; never commit credentials.

Migration 006 is rerunnable. It recreates named foreign keys after migration
004/005: `refresh_token_history.session_id` uses `ON UPDATE CASCADE` because
same-device login replaces `user_sessions.id`; user deletion remains cascading.

Migrations assume clean numeric-order application. Existing incompatible tables
are not generally repaired. Inspect partially migrated databases before running.

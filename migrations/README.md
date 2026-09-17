# Database migrations

Run SQL files in numeric order against Neon before deploying backend changes.

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/003_token_version.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_user_sessions.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/005_refresh_token_history.sql
```

Production uses `DATABASE_URL`; never commit credentials.

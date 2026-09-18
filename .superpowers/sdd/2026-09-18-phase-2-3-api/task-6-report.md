# Task 6: Verification and rollout

## Status

Blocked for Neon rollout. `DATABASE_URL` was unset, so live migration execution,
release schema verification, and zero-skip DB-backed tests could not run.

## Finalized artifacts

- API contract already documented in `docs/api.md` for Phase 2 transactions,
  categories, summary, and Phase 3 comparisons.
- Bruno requests already cover transaction CRUD/list/detail, category lifecycle,
  summary, comparison, and category comparison endpoints.
- Extended `scripts/verify_migrations.sh` to verify Phase 2 tables, required
  columns, indexes, and income starter category state.
- Extended `migrations/README.md` with Phase 2 release checks and verifier use.
- Preserved unrelated `bruno/ClariMoney_API/environments/local.yml` token edits.

## Verification evidence

- `./scripts/phase2_migration_test.sh` — passed.
- `JWT_SECRET='task6-test-secret-012345678901234567890' dart test` — passed;
  77 passed, 50 skipped DB-backed tests because `DATABASE_URL` was unset.
- `dart analyze` — passed; no diagnostics.
- `dart_frog build` — passed; existing rogue-route warning remains for
  `routes/api/v1/categories/[id].dart`.
- Bruno YAML parse — passed; 38 files parsed.
- `git diff --check` — passed.
- `./scripts/verify_migrations.sh` — blocked: `DATABASE_URL: DATABASE_URL is required`.

## Rogue route

Warning left unchanged. Renaming route can alter Dart Frog route resolution;
brief permits fix only when directly required and safe. Build succeeds despite
warning.

## Release gate

Run with production credentials before deploy:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/009_phase2_unified_transactions.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/010_phase2_unified_transactions_review_fixes.sql
./scripts/verify_migrations.sh
DATABASE_URL="$DATABASE_URL" JWT_SECRET="$JWT_SECRET" dart test
```

Do not commit credentials or token-filled local Bruno environment changes.

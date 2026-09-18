# Task 6: Verification and rollout

## Status

Neon migration and verifier passed. Shared focused-test DB helper now strips
unsupported `channel_binding` without changing production `.env`.

## Finalized artifacts

- API contract already documented in `docs/api.md` for Phase 2 transactions,
  categories, summary, and Phase 3 comparisons.
- Bruno requests already cover transaction CRUD/list/detail, category lifecycle,
  summary, comparison, and category comparison endpoints.
- Extended `scripts/verify_migrations.sh` to verify Phase 2 tables, exact
  constraints, indexes, triggers, and all five exact income starter rows.
- Extended `migrations/README.md` with Phase 2 release checks and verifier use.
- Sanitized tracked Bruno local token values.
- Extended `scripts/verify_release.sh` to apply migrations 009/010, remove
  unsupported `channel_binding`, run verifier, and fail skipped tests.
- Normalized PostgreSQL numeric aggregates in summary route.
- Added `test/support/test_database.dart`; focused Phase 2/3 fixtures use it.

## Verification evidence

- `./scripts/phase2_migration_test.sh` — passed.
- `./scripts/verify_release_test.sh` — passed; skip parser rejects compact and
  spaced skip markers.
- Safe `.env` release run — migrations 009/010 applied; verifier passed; tests
  ran with zero skips. Focused comparison, summary, and auth tests: 34 passed,
  1 failed. Remaining failure: existing UTC-boundary summary assertion expects
  `2`, Neon result is `3`; needs product/test-period decision, not connection
  handling.
- `dart analyze` — passed; no diagnostics.
- `dart_frog build` — passed; existing rogue-route warning remains for
  `routes/api/v1/categories/[id].dart`.
- Bruno YAML parse — passed; 38 files parsed.
- `git diff --check` — passed.
- `./scripts/verify_migrations.sh` — passed against Neon.

## Rogue route

Warning left unchanged. Renaming route can alter Dart Frog route resolution;
brief permits fix only when directly required and safe. Build succeeds despite
warning.

## Release gate

Run with production credentials before deploy. Script does not print credentials:

```bash
./scripts/verify_release.sh
```

Do not commit credentials or token-filled local Bruno environment changes.

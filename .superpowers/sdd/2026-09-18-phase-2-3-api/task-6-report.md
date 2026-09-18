# Task 6: Verification and rollout

## Status

Neon migration and verifier passed. Shared focused-test DB helper now strips
unsupported `channel_binding` without changing production `.env`. UTC boundary
fixture now asserts both offset forms at current start are included and prior
start remains previous-period data.

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
- Historical safe `.env` release run passed before final review fixes. It is not
  final release evidence.
- Final disposable release gate was not rerun; no disposable URL is claimed.
- `dart analyze` — passed; info-level style diagnostics remain.
- `dart_frog build` — passed; category route moved to
  `routes/api/v1/categories/[id]/index.dart`; no known rogue-route warning.
- Bruno YAML parse — passed; 38 files parsed.
- `git diff --check` — passed.
- `./scripts/verify_migrations.sh` — historical Neon result only; rerun against
  disposable release DB before deploy.

## Rogue route

Warning left unchanged. Renaming route can alter Dart Frog route resolution;
brief permits fix only when directly required and safe. Build succeeds despite
warning.

## Release gate

Run with disposable release credentials before deploy. No disposable Neon gate is claimed without `RELEASE_VERIFY_DATABASE_URL`. Script does not print credentials:

```bash
./scripts/verify_release.sh
```

Do not commit credentials or token-filled local Bruno environment changes.

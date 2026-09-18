# Task 6: Verification and rollout

## Status

Neon migration and verifier passed. Zero-skip release tests remain blocked by
existing `postgres` driver incompatibility with `.env` `channel_binding`, plus
existing DB assertions expecting numeric values instead of driver strings.

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

## Verification evidence

- `./scripts/phase2_migration_test.sh` — passed.
- `./scripts/verify_release_test.sh` — passed; skip parser rejects compact and
  spaced skip markers.
- Safe `.env` release run — migrations 009/010 applied; verifier passed; tests
  ran with zero skips but failed existing DB assertions after connection
  normalization. Failures include numeric string expectations and comparison
  route 500.
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

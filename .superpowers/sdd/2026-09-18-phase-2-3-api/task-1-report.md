# Task 1 report

## Status

Implemented migration 009 review corrections through migration 010 and updated
migration documentation.

## Changes

- Unified `transactions` with `type`, nullable `note`, positive amount, and `TIMESTAMPTZ` date.
- Backfilled existing transaction rows to `expense`.
- Added category `status` and `origin` lifecycle fields.
- Added income system categories: Salary, Bonus, Freelance, Gift, Other.
- Added category ownership/type/status trigger validation.
- Added note/name/status/type constraints and owner/type/date/search indexes.
- Added shell migration contract test.
- Added migration 010 preflight failures for invalid legacy amounts/category names.
- Preserved legacy date wall-clock values as UTC with `AT TIME ZONE 'UTC'`.
- Added category mutation guard for referenced transactions.
- Made income starter seed deterministic and exact-value upsert safe.
- Documented search index scope: equality/prefix only unless `pg_trgm` is added.
- Expanded migration contract checks for constraints, guard, seed rerun, timezone, and docs.

## Verification

- `scripts/phase2_migration_test.sh` passed.
- Neon migration applied with `psql ... migrations/009_phase2_unified_transactions.sql`.
- Neon migration 010 applied and rerun passed; five exact income starter categories present.
- Neon mutation probe passed; referenced category type mutation was rejected.
- `scripts/phase2_migration_test.sh` passed.
- `JWT_SECRET=<test value> dart test` passed: 35 passed, 44 total, 9 skipped.
- `dart analyze` passed.
- `dart_frog build` passed.
- `git diff --check` passed.

## Commit

Commit pending after corrective verification.

## Concerns

- Neon had zero existing transaction rows, so backfill was structurally verified but had no live rows to inspect.
- Direct `dart compile exe routes/index.dart` is not valid for Dart Frog route source because it has no `main`; `dart_frog build` is required.

## Review correction follow-up

- Moved migration 009 preflight before schema constraints and added an explicit
  UTC date conversion branch for legacy `timestamp without time zone` columns.
- Kept migration 009 runnable from migrations 001–008; added transaction scope
  and UTC session setting.
- Made migration 010 date conversion conditional on legacy column type, so
  reruns after 009 do not recast or conflict with existing constraints.
- Updated sequencing docs and migration contract tests.
- Applied and reran migrations 009 and 010 on Neon successfully.
- Working-tree edits in Bruno/local environment plus existing phase design/plan files remain untouched and unstaged.

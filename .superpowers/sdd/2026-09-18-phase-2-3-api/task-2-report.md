# Task 2 report

## Status

Implemented unified transaction and category APIs.

## Changes

- Added income and expense transaction create/update support.
- Preserved omitted `type` as legacy expense behavior.
- Enforced matching active category ownership/type checks.
- Added full ISO-8601 datetime validation and UTC response serialization.
- Added trimmed note validation with 500-character limit.
- Added transaction detail endpoint.
- Added search, type, period, category filters with AND semantics.
- Added deterministic date/created-time/ID ordering.
- Added category rename, archive, and reactivate endpoint for owned categories.
- Expanded category creation and listing for income/status/origin fields.
- Updated API docs and Bruno requests.

## Verification

- `JWT_SECRET='<test secret>' dart test` passed: 35 passed, 44 total, 9 skipped.
- `dart analyze` passed with existing project infos plus new style infos.
- `dart_frog build` passed.
- `scripts/phase2_migration_test.sh` passed.
- `git diff --check` passed.

## Concerns

- Neon-backed transaction route tests were unavailable in existing test harness; no new DB fixture test was added.
- Default `dart test` fails without configured `JWT_SECRET`; rerun with valid environment secret.
- Neon migration execution was not rerun because task environment exposed no safe database credential.
- Existing unrelated edits in `bruno/ClariMoney_API/environments/local.yml`, design docs, and plan files remain untouched and uncommitted.

## Review fixes

- Added shared malformed/non-object JSON decoding and typed-field validation.
- Added DB error handling for transaction detail/delete and category update.
- Preserved stored transaction type when update omits `type`.
- Escaped `%`, `_`, and `\\` in LIKE search parameters.
- Normalized whitespace-only notes to `null`.
- Added archived-category status documentation.
- Enforced non-null transaction categories in migration 010 with preflight guard.
- Added validation/unit and route malformed-payload tests.

## Review verification

- `JWT_SECRET='task2-review-test-secret-012345678901234567890' dart test`: passed, 51 passed, 44 existing DB-dependent tests skipped because no `DATABASE_URL` was exposed.
- `dart analyze`: passed with existing info-level lint notices.
- `dart_frog build`: passed.
- `scripts/phase2_migration_test.sh`: passed.
- `git diff --check`: passed.

## Review concerns

- Neon credential was not available for destructive/live migration execution.
- Requested Neon zero-skip run remains unverified; requires `DATABASE_URL` in execution environment.
- Existing suite has no transaction fixture coverage for income/expense CRUD, ownership, archive, filter ordering; focused malformed-payload and shared validation tests added without inventing a second DB harness.

## Re-review fixes

- Update loads existing transaction type before category validation.
- Omitted update type uses stored type; explicit mismatch returns 400.
- Database docs now match non-null category references and archive-only lifecycle.

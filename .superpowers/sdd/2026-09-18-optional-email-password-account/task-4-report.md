# Task 4 Report

Status: implemented.

## Changes

- Added `DELETE /api/v1/auth/account` at `routes/api/v1/auth/account/index.dart`.
- Required valid Bearer session through existing auth middleware.
- Required current password; verified with `PasswordUtils.verify`.
- Returned `401` for missing or incorrect password without deletion.
- Deleted user inside `Pool.runTx`; existing FK cascades remove categories,
  transactions, sessions, and auth tokens.
- Returned `200` only after transaction commit.
- Added Neon-backed tests for valid deletion, wrong password, missing password,
  and cascade cleanup.
- Documented irreversible behavior in `docs/api.md`.

## Verification

- `dart test test/routes/account_routes_test.dart`: compiled; 3 tests skipped
  because local `DATABASE_URL` was unset.
- `JWT_SECRET=test-only-secret-with-at-least-32-chars-1234 dart test`: passed
  non-DB tests; Neon-backed tests skipped because `DATABASE_URL` was unset.
- `dart analyze`: passed with existing informational lints only.
- `dart_frog build`: passed.

## Concern

Task brief names `routes/api/v1/auth/account.dart`. Dart Frog rejects that file
when sibling middleware directory exists, reporting a rogue route. Framework-
valid route is `routes/api/v1/auth/account/index.dart`, preserving endpoint URL.

Unrelated working-tree edits were not staged. No secrets added.

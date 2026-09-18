# Task 3 Report: Forgot/reset password

## Status

Implemented.

## Changes

- Added public `POST /api/v1/auth/forgot-password`.
- Added public `POST /api/v1/auth/reset-password`.
- Normalized email before lookup.
- Added 30-minute `password_reset` tokens through `AuthTokenService`.
- Kept forgot-password response generic for existing, missing, invalid, and delivery-failure cases.
- Consumed reset tokens transactionally and once.
- Enforced eight-character minimum password.
- Updated password hash transactionally.
- Incremented `users.token_version`.
- Revoked all user sessions in same transaction through `SessionService`.
- Added Neon-backed route tests and API documentation.

## Verification

- `dart analyze`: passed.
- `dart test test/routes/password_reset_routes_test.dart` with `.env` values parsed safely: passed, 3 tests.
- `dart test` with `.env` values parsed safely: passed, 68 tests.
- `dart_frog build`: passed.
- Default `dart test` without environment: pre-existing JWT-secret failures; DB tests skipped. No secrets committed.

## Commit

Recorded in final response after commit.

## Concerns

- Forgot-password delivery errors intentionally return the same success response to prevent account enumeration.
- Existing unrelated Bruno/docs changes remained unstaged.

## Review follow-up

- Added a 250 ms minimum forgot-password response duration for existing, missing,
  invalid, and delivery-failure paths. No infrastructure added.
- Preserved generic success response. No raw token logging added.
- Added Neon-backed coverage for email normalization, SMTP rollback, prior-token
  invalidation, wrong purpose, exact 30-minute lifetime, and old access-token
  rejection after `token_version` increment/session revocation.

## Follow-up verification

- Focused Neon suite: 9 passed.
- Full Neon-backed suite: 74 passed.
- `dart analyze`: passed with existing informational lints only.
- `dart_frog build`: passed.

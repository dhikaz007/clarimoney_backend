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

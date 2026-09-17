# Task 3 Report

## Status

Complete.

## Changes

- Added required, trimmed, maximum-255-character `device_id` validation to login/register.
- Added optional `device_name` handling.
- Captured request `User-Agent`.
- Replaced direct JWT issuance with `SessionService.createSession`.
- Added `access_token`, `refresh_token`, and `session_id` response fields.
- Preserved `token` as access-token alias.
- Updated auth API docs and `400` validation responses.
- Added missing-device and registration response-shape route tests.

## Tests

- `dart format --output=none --set-exit-if-changed routes test` — passed.
- `dart analyze` — passed.
- `JWT_SECRET='test-secret-with-at-least-32-characters' dart test` — passed: 14 passed, 4 skipped.
- `dart test test/routes/auth_routes_test.dart` — passed: 4 passed, 1 skipped.

Plain `dart test` fails existing JWT tests when `JWT_SECRET` is unset. Authenticated test run passes.

## Concerns

- Registration response test requires configured `DATABASE_URL` and skips otherwise.
- `device_name` is not independently length-validated; DB column caps it at 255 and route preserves existing catch/error semantics.

## Review Fixes

- Moved registration user insert and session creation into one DB transaction; failed session creation rolls back user creation.
- Added login response-shape coverage.
- Added same-device session replacement and metadata coverage.
- Added invalid `device_id` value/type coverage for both routes.
- Added non-string `device_name` rejection coverage.
- Replaced inaccurate `Device ID required` with bounded validation message.
- Added concrete validation and invalid-credential error response examples to docs.

## Review-Fix Verification

- `dart analyze` — passed.
- `JWT_SECRET='test-secret-with-at-least-32-characters' dart test` — passed: 25 passed, 7 skipped.
- No migration changes needed; existing `004_user_sessions.sql` supports required behavior.

## Final Review Fix

- Corrected same-device test to match intentional SQL upsert behavior: `session_id` remains stable.
- Test now verifies refresh-token rotation, metadata update, one active session, old refresh-token rejection, and session revocation on reuse.

## Final Verification

- `dart test test/routes/auth_routes_test.dart` — passed: 16 passed, 4 skipped.

# Task 2 Report

## Status

Implemented access-token expiry and session lifecycle service.

## Changes

- Changed `JwtUtils` access-token expiry from 7 days to 15 minutes.
- Preserved `sub` and `ver` claims.
- Added `SessionService.createSession` with device metadata persistence.
- Stored SHA-256 refresh-token hashes only.
- Added 30-day refresh-token expiry.
- Added transactional refresh-token lookup, expiry validation, revocation validation, rotation, and `last_used_at` update.
- Added `revokeSession` and `revokeAll`.
- Added expiry/claims and refresh-lifetime tests.

## Tests

- `rtk dart analyze` — passed; no issues.
- `JWT_SECRET='12345678901234567890123456789012' rtk dart test` — passed; 12 tests.
- Initial `rtk dart test` without `JWT_SECRET` — failed as expected because `JwtUtils` requires a 32-character secret.
- `rtk dart format ...` — passed.
- `rtk git diff --check` — passed.

## Concerns

- No DB-backed session tests run because no test database setup exists in repository.
- Existing `user_sessions` schema has one refresh hash per session. After rotation, replaced hashes cannot identify a reused prior token, so reuse detection cannot revoke current replacement session without a token-family/reuse-history schema change. Current implementation returns null for unknown/revoked tokens and revokes expired or already-invalid rows.
- `createSession` replaces existing `(user_id, device_id)` session through schema conflict handling.

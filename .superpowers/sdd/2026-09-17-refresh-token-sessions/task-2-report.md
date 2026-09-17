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

## Review Fixes

- Added Neon-backed concurrent reuse test. Two simultaneous rotations yield one token pair; second request detects consumed history row and revokes session.
- Added Neon-backed invalid-JWT test using injected generator; transaction leaves no active session after generator failure.
- Added `SessionService` generator injection without changing runtime default.
- Documented migrations 001–005 in `README.md` and `migrations/README.md`.
- Reapplied migration 005 to Neon successfully; idempotent notices expected, `INSERT 0 0`.

## Review Test Results

- `rtk dart analyze` — passed.
- Full suite with `.env` credentials — passed; 15 tests.
- Neon-backed concurrent reuse test — passed.
- Neon-backed invalid-JWT rollback test — passed.
- `rtk git diff --check` — passed.

## Review Fixes

- Added `migrations/005_refresh_token_history.sql`: durable token history with consumed state, session linkage, expiry, index, and existing-session backfill.
- Rotation locks history rows, consumes presented tokens, records replacement tokens, checks `RETURNING` and `affectedRows`, and revokes session on reuse or failed state transition.
- Concurrent reuse serializes on row lock; second request sees consumed token and revokes current session.
- Access JWT generation now precedes DB writes; invalid JWT configuration cannot leave active session.
- Added Neon-backed reuse test. Test sanitizes unsupported `channel_binding` URL parameter for Dart Postgres client.
- Applied migration to Neon: `CREATE TABLE`, `CREATE INDEX`, `INSERT 0 0`.

## Review Test Results

- `rtk dart analyze` — passed.
- Full suite with `.env` credentials — passed; 13 tests.
- `rtk git diff --check` — passed.

## Concerns

- No DB-backed session tests run because no test database setup exists in repository.
- Existing `user_sessions` schema has one refresh hash per session. After rotation, replaced hashes cannot identify a reused prior token, so reuse detection cannot revoke current replacement session without a token-family/reuse-history schema change. Current implementation returns null for unknown/revoked tokens and revokes expired or already-invalid rows.
- `createSession` replaces existing `(user_id, device_id)` session through schema conflict handling.

## Review Fixes

- Added `migrations/005_refresh_token_history.sql` with durable token-family history and backfill for existing sessions.
- Rotation now locks token history and session state in one transaction, marks presented tokens consumed, records replacements, and revokes session on consumed-token reuse.
- Concurrent reuse serializes on `FOR UPDATE`; loser sees `consumed_at` and revokes current session.
- Rotation checks `RETURNING id` and `affectedRows`; failed state transitions return null.
- Access JWT is generated before session persistence, so invalid JWT configuration rolls back session creation.
- Added DB-backed reuse test. Test skips when DB/JWT configuration unavailable.
- Applied migration to Neon successfully: `CREATE TABLE`, `CREATE INDEX`, `INSERT 0 0`.

## Review Test Results

- `rtk dart analyze` — passed; no issues.
- `JWT_SECRET='12345678901234567890123456789012' rtk dart test` — passed; 12 tests, 1 DB test skipped.
- `rtk git diff --check` — passed.

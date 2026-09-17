# Task 1 Report

## Scope

Implemented session schema and refresh-token utilities from Task 1 brief.

## Migration

Added `migrations/004_user_sessions.sql`:

- `user_sessions` table with UUID primary key.
- Required `user_id` foreign key to `users`, cascading on user deletion.
- Unique `(user_id, device_id)` constraint.
- Hashed token storage in fixed-width `CHAR(64)` `refresh_token_hash` column.
- Device metadata: `device_name`, `user_agent`.
- Lifecycle timestamps: `created_at`, `expires_at`, `revoked_at`, `last_used_at`.
- Indexes on `(user_id, revoked_at)` and `refresh_token_hash`.
- Migration is idempotent through `IF NOT EXISTS` clauses.

## Utility

Added `lib/src/utils/refresh_token_utils.dart`:

- `RefreshTokenUtils.generate()` creates 32 bytes using `Random.secure()`.
- Encodes tokens as unpadded base64url strings.
- `RefreshTokenUtils.hash()` returns stable SHA-256 lowercase hexadecimal digest.

## Tests

Added `test/src/utils/refresh_token_utils_test.dart`:

- Verifies two generated tokens differ.
- Verifies token shape and expected size.
- Verifies stable SHA-256 output for a known token.

Commands:

- `dart test test/src/utils/refresh_token_utils_test.dart` — passed, 2 tests.
- `JWT_SECRET='test-secret-with-at-least-32-characters' dart test` — passed, 10 tests.
- `dart format --output=none --set-exit-if-changed lib/src/utils/refresh_token_utils.dart test/src/utils/refresh_token_utils_test.dart` — passed.
- `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_user_sessions.sql` — blocked: `DATABASE_URL` was unavailable; `psql` attempted local socket `/tmp/.s.PGSQL.5432`, which was not running.

## Constraints

No unrelated files changed. Neon migration remains unapplied and needs rerun with valid `DATABASE_URL`.

## Review Fixes

- Reused one `Random.secure()` instance per generated token.
- Strengthened token test to require exact 43-character unpadded Base64URL output.
- Applied `migrations/004_user_sessions.sql` to configured Neon database from `.env` with `ON_ERROR_STOP=1`.

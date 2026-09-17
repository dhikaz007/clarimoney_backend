# Refresh Token and Device Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-device sessions, rotating refresh tokens, session inspection, device logout, all-device logout, and mobile splash-compatible auth state.

**Architecture:** Store one hashed refresh token per login session in PostgreSQL. Issue short-lived access JWTs plus long-lived opaque refresh tokens. Rotate refresh tokens on refresh; revoke the session on reuse, logout, expiry, or explicit device removal. Keep existing `token_version` as global emergency revoke.

**Tech Stack:** Dart Frog, PostgreSQL/Neon, `dart_jsonwebtoken`, `crypto`, Bruno collection.

## Global Constraints

- Access token lifetime: 15 minutes.
- Refresh token lifetime: 30 days.
- Raw refresh tokens never enter DB.
- `device_id` comes from mobile secure storage; `device_name` is display metadata.
- Existing protected endpoints keep Bearer access-token auth.
- Existing `POST /api/v1/auth/logout` behavior becomes current-device logout.
- `POST /api/v1/auth/logout-all` revokes every user session.

---

### Task 1: Session schema and token utilities

**Files:**
- Create: `migrations/004_user_sessions.sql`
- Create: `lib/src/utils/refresh_token_utils.dart`
- Test: `test/src/utils/refresh_token_utils_test.dart`

**Interfaces:**
- `RefreshTokenUtils.generate()` returns a cryptographically random opaque token.
- `RefreshTokenUtils.hash(String token)` returns a stable SHA-256 hex digest.

- [ ] Add `user_sessions` with UUID ID, user FK, unique device ID per user, token hash, device metadata, timestamps, expiry, revoked timestamp, and last-used timestamp.
- [ ] Add indexes for `(user_id, revoked_at)` and `refresh_token_hash`.
- [ ] Generate 32 random bytes with `Random.secure`; encode base64url without padding.
- [ ] Test generated tokens differ and hash output stays stable.
- [ ] Run `dart test test/src/utils/refresh_token_utils_test.dart`.
- [ ] Apply migration to Neon with `psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/004_user_sessions.sql`.

### Task 2: Access and refresh token service

**Files:**
- Modify: `lib/src/utils/jwt_utils.dart`
- Create: `lib/src/auth/session_service.dart`
- Test: `test/src/auth/session_service_test.dart`

**Interfaces:**
- `SessionService.createSession({required String userId, required String deviceId, String? deviceName, String? userAgent})` returns `{sessionId, accessToken, refreshToken}`.
- `SessionService.rotateRefreshToken(String refreshToken)` returns new access/refresh token pair or null.
- `SessionService.revokeSession(String sessionId, String userId)` returns bool.
- `SessionService.revokeAll(String userId)` returns count.

- [ ] Change access JWT expiry from 7 days to 15 minutes; keep `sub`, `ver` claims.
- [ ] Make session service insert only refresh-token hash, never raw token.
- [ ] Enforce refresh expiry and revoked checks.
- [ ] Rotate atomically: revoke old session token state, create replacement token hash, update `last_used_at`; token reuse returns null and revokes session.
- [ ] Test expiry, rotation, invalid token, revoked session, and device metadata persistence with DB-backed test setup or focused pure utility tests where DB is unavailable.

### Task 3: Login and registration session creation

**Files:**
- Modify: `routes/api/v1/auth/login.dart`
- Modify: `routes/api/v1/auth/register.dart`
- Modify: `docs/api.md`

**Interfaces:**
- Login/register JSON accepts `device_id` required and `device_name` optional.
- Auth response data returns `access_token`, `refresh_token`, `session_id`; retain `token` alias temporarily for existing Bruno/mobile clients.

- [ ] Validate `device_id` as non-empty, bounded string.
- [ ] Read `device_name` and request User-Agent.
- [ ] Create or replace session for same user/device ID.
- [ ] Return 201 register and 200 login with access/refresh/session fields.
- [ ] Update API docs and error responses.
- [ ] Add route tests for missing device ID and successful response shape.

### Task 4: Refresh endpoint and auth session endpoints

**Files:**
- Create: `routes/api/v1/auth/refresh.dart`
- Create: `routes/api/v1/auth/sessions.dart`
- Create: `routes/api/v1/auth/sessions/[id].dart`
- Create: `routes/api/v1/auth/logout_all.dart`
- Modify: `routes/api/v1/auth/logout.dart`

**Interfaces:**
- `POST /api/v1/auth/refresh` body `{ "refresh_token": "..." }` returns rotated access and refresh tokens.
- `GET /api/v1/auth/sessions` returns current user active sessions without token hashes.
- `DELETE /api/v1/auth/sessions/:id` revokes one owned session.
- `POST /api/v1/auth/logout` revokes current session identified by access JWT `sid` claim.
- `POST /api/v1/auth/logout-all` revokes all sessions for authenticated user.

- [ ] Add `sid` claim to access JWT and validate current token version in middleware.
- [ ] Require refresh token body for refresh endpoint; return 401 for invalid/revoked/expired token.
- [ ] Ensure session endpoints only affect authenticated owner.
- [ ] Make logout idempotent enough for mobile retry, without exposing whether another user owns a session ID.
- [ ] Test refresh rotation, current-device logout, all-device logout, and cross-user session access denial.

### Task 5: Bruno collection and verification

**Files:**
- Create: `bruno/ClariMoney_API/Auth/Refresh.yml`
- Create: `bruno/ClariMoney_API/Auth/Sessions.yml`
- Create: `bruno/ClariMoney_API/Auth/Logout All.yml`
- Modify: `bruno/ClariMoney_API/Auth/login.yml`
- Modify: `bruno/ClariMoney_API/Auth/register.yml`
- Modify: `bruno/ClariMoney_API/Auth/logout.yml`
- Modify: `bruno/ClariMoney_API/environments/local.yml`

- [ ] Add `device_id`, `device_name`, and `refresh_token` environment variables.
- [ ] Save access token, refresh token, session ID, and user ID in after-response scripts.
- [ ] Add requests for refresh, list sessions, current-device logout, device logout, and all-device logout.
- [ ] Verify sequence: login → protected request → refresh → old refresh rejected → sessions list → logout → access rejected → login again → logout-all.
- [ ] Run `dart format --output=none --set-exit-if-changed lib routes test`.
- [ ] Run `JWT_SECRET='test-secret-with-at-least-32-characters' dart test`.
- [ ] Run `dart analyze && dart_frog build`.

## Self-review

- Coverage: schema, hashing, access/refresh lifecycle, login/register, refresh, per-device sessions, current-device logout, all-device logout, Bruno, tests.
- No raw refresh token is persisted.
- Access JWT and session interfaces carry `sid` consistently.
- Existing `token` alias prevents immediate client breakage during migration.

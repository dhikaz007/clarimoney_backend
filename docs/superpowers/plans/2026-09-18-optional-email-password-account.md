# Optional Email Verification, Password Reset, and Account Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional profile email verification, Gmail SMTP delivery, password reset, and permanent account deletion.

**Architecture:** Store hashed one-time auth tokens in PostgreSQL. Send verification/reset links through Gmail SMTP. Keep registration and login available before email verification. Reset and deletion revoke dependent sessions through existing token-version/session logic.

**Tech Stack:** Dart Frog, PostgreSQL/Neon, `mailer`, `crypt`, `crypto`, Bruno.

## Global Constraints

- Register remains successful without verified email.
- SMTP credentials remain in `.env`; never commit or log them.
- Verification token expiry: 24 hours.
- Password reset token expiry: 30 minutes.
- Raw verification/reset tokens never enter DB.
- Forgot-password response never reveals account existence.
- Reset password revokes every device session.
- Account deletion is permanent and requires current password.
- Password minimum length remains 8 characters.
- Existing access/refresh/session behavior remains compatible.

---

### Task 1: Dependencies, schema, token and mail services

**Files:**
- Modify: `pubspec.yaml`
- Create: `migrations/007_auth_tokens_email_verification.sql`
- Create: `lib/src/utils/auth_token_utils.dart`
- Create: `lib/src/services/email_service.dart`
- Create: `lib/src/services/auth_token_service.dart`
- Modify: `.env.example`
- Modify: `README.md`
- Test: `test/src/utils/auth_token_utils_test.dart`
- Test: `test/src/services/email_service_test.dart`

**Interfaces:**
- `AuthTokenUtils.generate()` returns opaque random token.
- `AuthTokenUtils.hash(String token)` returns SHA-256 hex.
- `EmailService.sendVerification(...)` and `sendPasswordReset(...)` send Gmail SMTP mail or throw controlled configuration/send errors.
- `AuthTokenService.issue(userId, purpose, lifetime)` returns raw token plus expiry while persisting only hash.
- `AuthTokenService.consume(token, purpose)` atomically returns user ID or null.

- [x] Add `mailer` dependency without adding another token/hash dependency.
- [x] Create `email_verified_at` on `users`.
- [x] Create `auth_tokens` with UUID, user FK cascade, unique hash, purpose constraint, expiry, used timestamp, created timestamp, and indexes.
- [x] Read `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, and `SMTP_FROM` only from environment.
- [x] Use Gmail SMTP defaults only when explicitly configured; missing values produce controlled errors.
- [x] Build links from `APP_BASE_URL`, never log raw tokens.
- [x] Test token uniqueness/hash, missing SMTP configuration, and email service message construction.
- [x] Apply migration 007 to Neon.
- [x] Document `.env` values and Google App Password setup.

### Task 2: Optional email verification and profile endpoint

**Files:**
- Modify: `routes/api/v1/auth/register.dart`
- Create: `routes/api/v1/auth/me/index.dart`
- Create: `routes/api/v1/auth/resend_verification/index.dart`
- Create: `routes/api/v1/auth/verify_email.dart`
- Modify: `lib/src/auth_middleware.dart`
- Modify: `docs/api.md`
- Test: `test/routes/email_verification_routes_test.dart`

**Interfaces:**
- `GET /api/v1/auth/me` returns `id`, `email`, `email_verified`.
- `POST /api/v1/auth/resend-verification` requires Bearer access token and returns generic success.
- `POST /api/v1/auth/verify-email` accepts `{ "token": "..." }` publicly.

- [x] Add `email_verified_at` to register response/profile state without blocking registration.
- [x] Resend invalidates prior unused verification tokens, issues 24-hour token, sends email.
- [x] Already verified resend returns success without sending mail.
- [x] Verify consumes one token atomically and marks user verified.
- [x] Invalid, expired, or reused token returns generic `400`.
- [x] Test registration before verification, profile state, resend invalidation, success, expiry, and reuse.

### Task 3: Forgot/reset password

**Files:**
- Create: `routes/api/v1/auth/forgot_password.dart`
- Create: `routes/api/v1/auth/reset_password.dart`
- Modify: `lib/src/auth/session_service.dart`
- Modify: `docs/api.md`
- Test: `test/routes/password_reset_routes_test.dart`

**Interfaces:**
- `POST /api/v1/auth/forgot-password` accepts `{ "email": "..." }` and always returns same success response.
- `POST /api/v1/auth/reset-password` accepts `{ "token": "...", "password": "..." }`.

- [x] Normalize email before lookup.
- [x] Issue 30-minute reset token only for existing user; send no distinguishing response.
- [x] Consume token once; reject invalid, expired, reused, or weak-password requests generically.
- [x] Update password hash inside transaction.
- [x] Increment `users.token_version` and revoke all `user_sessions` after successful reset.
- [x] Test identical forgot responses for existing/non-existing email, success, expiry, reuse, weak password, and session revocation.

### Task 4: Permanent account deletion

**Files:**
- Create: `routes/api/v1/auth/account/index.dart`
- Modify: `docs/api.md`
- Test: `test/routes/account_routes_test.dart`

**Interfaces:**
- `DELETE /api/v1/auth/account` requires Bearer access token and body `{ "password": "..." }`.

- [x] Verify current password with existing `PasswordUtils.verify`.
- [x] Return `401` for wrong password without deleting data.
- [x] Delete user in transaction; rely on FK cascades for categories, transactions, sessions, and auth tokens.
- [x] Return `200` confirmation only after commit.
- [x] Test valid deletion, wrong password, missing password, cascade cleanup, and deleted-token rejection.
- [x] Document irreversible behavior.

### Task 5: Bruno collection, docs, tests, release

**Files:**
- Modify: `bruno/ClariMoney_API/environments/local.yml`
- Create: `bruno/ClariMoney_API/Auth/Me.yml`
- Create: `bruno/ClariMoney_API/Auth/Resend Verification.yml`
- Create: `bruno/ClariMoney_API/Auth/Verify Email.yml`
- Create: `bruno/ClariMoney_API/Auth/Forgot Password.yml`
- Create: `bruno/ClariMoney_API/Auth/Reset Password.yml`
- Create: `bruno/ClariMoney_API/Auth/Delete Account.yml`
- Modify: `migrations/README.md`

- [x] Add `verification_token`, `reset_token`, and `email_verified` variables without storing secrets in committed environments.
- [x] Add request scripts for response fields only; never print raw SMTP credentials.
- [x] Add examples and expected failure responses.
- [x] Validate YAML collection structure.
- [x] Run `DATABASE_URL=... JWT_SECRET=... dart test` with Neon-backed tests.
- [x] Run `dart analyze`, `dart_frog build`, and `git diff --check`.
- [x] Document migration 007 ordering, Gmail App Password setup, and required release env vars.

## Self-review

- Spec coverage: SMTP, token storage, optional verification, profile state, reset flow, session revocation, deletion cascade, Bruno, tests, docs.
- No raw auth tokens or SMTP secrets committed.
- Register/login remain unblocked by verification.
- Reset/delete invalidates sessions.

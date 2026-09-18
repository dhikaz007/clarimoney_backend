# Optional Email Verification, Password Reset, and Account Deletion

## Goal

Add optional profile email verification, forgot/reset password, and permanent account deletion without blocking registration or initial app access.

## Email delivery

Development/local uses Gmail SMTP:

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your@gmail.com
SMTP_PASSWORD=google-app-password
SMTP_FROM=your@gmail.com
```

Credentials remain in `.env`; never commit or log them. Missing SMTP configuration returns a controlled server error for email-send operations. Register never sends verification email automatically.

## Database

Add nullable `users.email_verified_at`.

Add one-time token table with:

- `id UUID`.
- `user_id UUID` with cascade delete.
- `token_hash VARCHAR` unique.
- `purpose` constrained to `email_verification` or `password_reset`.
- `expires_at`.
- `used_at` nullable.
- `created_at`.

Add indexes for user/purpose and token hash. Store only SHA-256 token hashes.

## API

### `GET /api/v1/auth/me`

Authenticated. Returns user ID, email, and `email_verified`.

### `POST /api/v1/auth/resend-verification`

Authenticated. Generates a 24-hour one-time token, invalidates prior unused verification tokens for user, sends email. Already verified returns successful idempotent response without sending.

### `POST /api/v1/auth/verify-email`

Public. Body `{ "token": "..." }`. Validates unused, unexpired verification token, marks `email_verified_at`, marks token used. Invalid token returns `400` or `401` without revealing user details.

### `POST /api/v1/auth/forgot-password`

Public. Body `{ "email": "..." }`. Always returns same success response whether email exists. Existing user receives 30-minute one-time reset email. Do not reveal account existence.

### `POST /api/v1/auth/reset-password`

Public. Body `{ "token": "...", "password": "..." }`. Requires password minimum 8 characters. Valid token updates password, marks token used, increments `token_version`, revokes all sessions. Invalid/expired/used token returns generic `400`.

### `DELETE /api/v1/auth/account`

Authenticated. Body `{ "password": "..." }`. Verifies current password, deletes user in transaction. Existing foreign keys cascade categories, transactions, sessions, and auth tokens. Operation irreversible. Invalid password returns `401`.

## Security

- Register remains successful without verified email.
- Login remains allowed before verification.
- Verification/reset raw tokens never enter DB or logs.
- Reset requests use generic response and bounded email work.
- Reset password revokes every device session.
- Account deletion requires current access token plus current password.
- Account deletion returns no recoverable account data.
- SMTP App Password only; Gmail primary password prohibited.

## Mobile profile flow

```text
Profile opens → GET /auth/me
email_verified=false → show Verify email
tap Verify → POST /auth/resend-verification
user submits token/link → POST /auth/verify-email
profile reloads → email_verified=true
```

## Tests

- Registration still succeeds with unverified email.
- `/auth/me` reports verification state.
- Verification success, expiry, reuse, and invalid token.
- Resend invalidates prior token.
- Forgot password response identical for existing/non-existing email.
- Reset success, expiry, reuse, weak password, session revocation.
- Account deletion valid/invalid password and cascade cleanup.
- SMTP missing configuration returns controlled error.

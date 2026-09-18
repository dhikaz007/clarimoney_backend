# Task 1 Report

Status: complete.

Implemented:
- Added `mailer` dependency.
- Added migration 007 for `email_verified_at` and `auth_tokens`.
- Added opaque token generation and SHA-256 hashing.
- Added SMTP email service with environment-only configuration, link building, and controlled errors.
- Added transactional token issue/consume service.
- Added token and email service tests.
- Documented environment variables, Gmail App Password setup, and migration order.

Verification:
- `JWT_SECRET='local-test-secret-with-at-least-32-characters' dart test` passed: 33 tests, 13 expected skips.
- `dart analyze` passed with 4 pre-existing info diagnostics.
- `dart_frog build` passed.
- `git diff --check` passed.

Migration:
- Not applied to Neon. `DATABASE_URL` was not configured in shell; local `.env` was not read to avoid exposing secrets.

Commit: `0afdcff` (`feat: add auth token and email foundation`).

Concerns:
- Full test run without `JWT_SECRET` fails two pre-existing JWT tests by design. Secret-injected run passes.
- SMTP sends require all documented variables, including `APP_BASE_URL`.

Follow-up commit: `98de3e4` (`test: verify auth token persistence and consumption`).

## Follow-up findings fixed

- Applied migration 007 to configured Neon using repository `.env` in a subprocess;
  secrets were not printed or committed.
- Preserved the unique `token_hash` index and added legacy-index cleanup in
  migration 008.
- Added Neon-backed `AuthTokenService` tests for hash-only persistence, success, expiry,
  used-token rejection, wrong-purpose rejection, and concurrent consumption.
- Strengthened SMTP tests for every missing configuration key and invalid port.
- Earlier local run: `dart test` passed 51 tests with database-backed coverage;
  release-gate result is recorded only in Task 5 report.

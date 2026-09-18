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

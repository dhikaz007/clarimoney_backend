# ClariMoney Backend

[![style: dart frog lint][dart_frog_lint_badge]][dart_frog_lint_link]
[![License: MIT][license_badge]][license_link]
[![Powered by Dart Frog](https://img.shields.io/endpoint?url=https://tinyurl.com/dartfrog-badge)](https://dart-frog.dev)

Dart Frog API for ClariMoney. Neon PostgreSQL backend.

## Local setup

```bash
cp .env.example .env
export DATABASE_URL='postgresql://...'
export JWT_SECRET='at-least-32-random-characters'
export ALLOWED_ORIGIN='http://localhost:3000'
dart pub get
dart_frog dev
```

Apply migrations before starting production:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
```

## Verification

```bash
dart format --output=none --set-exit-if-changed .
dart analyze
JWT_SECRET='test-secret-with-at-least-32-characters' dart test
dart_frog build
```

Production requirements:
- Rotate any Neon credential exposed outside secret storage.
- Set `DATABASE_URL`, `JWT_SECRET`, and `ALLOWED_ORIGIN` in deployment secrets.
- Never commit `.env`.

## Render Free deployment

1. Push this repository to GitHub.
2. In Render, create a Blueprint from the repository.
3. Render reads `render.yaml` and builds `Dockerfile`.
4. Set `DATABASE_URL` to Neon connection string.
5. Set `ALLOWED_ORIGIN` to the allowed client origin.
6. Apply migrations against Neon before first deploy.

Render Free sleeps after inactivity. First request after sleep has cold-start delay.
Neon remains the persistent database; Render filesystem is ephemeral.

[dart_frog_lint_badge]: https://img.shields.io/badge/style-dart_frog_lint-1DF9D2.svg
[dart_frog_lint_link]: https://pub.dev/packages/dart_frog_lint
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT

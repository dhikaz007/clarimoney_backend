# ClariMoney Backend

Dart Frog REST API, Neon PostgreSQL, JWT authentication.

## Flow

```text
HTTP request
  -> root middleware: logger, CORS, PostgreSQL pool
  -> feature auth middleware
  -> route handler
  -> Neon PostgreSQL
```

Root middleware creates one PostgreSQL pool per server process. Protected routes read user ID from verified JWT context.

## Environment

```text
DATABASE_URL=postgresql://...
JWT_SECRET=random-secret-minimum-32-characters
ALLOWED_ORIGIN=https://client.example.com
```

Required in deployment. No production secret fallback.

## Response

```json
{
  "status_code": 200,
  "message": "Operation succeeded",
  "data": null
}
```

Transaction pagination adds metadata directly at response root:

```json
{
  "status_code": 200,
  "message": "Transactions fetched successfully",
  "data": [],
  "page": 1,
  "limit": 10,
  "total": 0,
  "total_pages": 0,
  "has_next": false
}
```

## Authentication flow

```text
register -> validate -> check email -> hash password -> insert user -> issue JWT
login    -> normalize email -> load hash -> verify password -> issue JWT
request  -> read Bearer token -> verify JWT -> provide user ID -> route
```

Register and login are public. Categories, transactions, and summary require `Authorization: Bearer <token>`.

## Routes

| Method | Path | Auth | Purpose |
|---|---|---:|---|
| GET | `/` | No | Health check and DB connectivity |
| POST | `/api/v1/auth/register` | No | Create user |
| POST | `/api/v1/auth/login` | No | Authenticate user |
| GET | `/api/v1/categories` | Yes | List categories |
| POST | `/api/v1/categories` | Yes | Create expense category |
| GET | `/api/v1/transactions?page=1&limit=10` | Yes | List transactions |
| POST | `/api/v1/transactions` | Yes | Create transaction |
| PUT | `/api/v1/transactions/:id` | Yes | Update owned transaction |
| DELETE | `/api/v1/transactions/:id` | Yes | Delete owned transaction |
| GET | `/api/v1/summary/overview?period=this_month` | Yes | Spending summary |
| GET | `/api/v1/summary/comparison?period=this_month` | Yes | Income, expense, and cash-flow comparison |
| GET | `/api/v1/summary/comparison/categories?period=this_month` | Yes | Category comparison list |
| GET | `/api/v1/categories/:id/comparison?period=this_month` | Yes | Single-category comparison |

## Validation

- Email normalized lowercase.
- Password minimum 8 characters.
- Amount greater than zero.
- Category type `expense` only.
- Color format `#RRGGBB`.
- Duplicate category names rejected case-insensitively.
- Transactions accept system categories or current-user categories.
- Update/delete filter by current user ID.
- Pagination default 10, maximum 100.
- Summary periods: `this_month`, `previous_month`.

## Database

Run migrations in order:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
```

Tables: `users`, `categories`, `transactions`.

Indexes: `idx_transactions_user_date`, `idx_categories_user`, `uq_categories_owner_name_type`.

## Error flow

```text
400 validation | 401 auth | 404 missing resource | 405 method | 409 duplicate | 500 database
```

Internal exception details stay server-side.

## Verification

```sh
dart format --output=none --set-exit-if-changed .
dart analyze
JWT_SECRET='test-secret-with-at-least-32-characters' dart test
dart_frog build
docker build -t clarimoney-backend:local .
```

Unit tests cover password hashing, JWT verification, auth middleware, and invalid auth input. Database integration tests need a dedicated test database.

## Deployment

Render reads `render.yaml`, builds `Dockerfile`, and injects secrets. Render filesystem is ephemeral; Neon stores persistent data. Rotate any exposed Neon credential before public deployment.

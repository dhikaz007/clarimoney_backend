# ClariMoney API

Base URL lokal:

```text
http://localhost:8080
```

Render memakai URL service `onrender.com`.

## Response envelope

Success/error response:

```json
{
  "status_code": 200,
  "message": "Operation succeeded",
  "data": null
}
```

Pagination fields berada langsung di root response:

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

## Authentication

Protected endpoints memakai:

```http
Authorization: Bearer <access_token>
```

Public:

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/verify-email`
- `POST /api/v1/auth/forgot-password`
- `POST /api/v1/auth/reset-password`

Protected auth:

- `GET /api/v1/auth/me`
- `POST /api/v1/auth/resend-verification`
- `DELETE /api/v1/auth/account`

Email verification remains optional. Registration and login succeed before
verification.

Protected:

- Categories.
- Transactions.
- Summary.

## Transaction API

All transaction endpoints require JWT. Amounts are positive values with at most
two decimal places. `type` is `income` or `expense`; omitted `type` means
`expense` for legacy clients. Both types require an active category of matching
type. Dates require full ISO-8601 datetime input and return UTC ISO strings.

- `GET /api/v1/transactions?page=1&limit=10&type=all&period=this_month&category_id=&search=`
- `POST /api/v1/transactions`
- `GET /api/v1/transactions/:id`
- `PUT /api/v1/transactions/:id`
- `DELETE /api/v1/transactions/:id`

Create/update body:

```json
{"type":"income","category_id":"uuid","amount":12500000,"date":"2026-09-15T08:30:00.000Z","note":"Monthly salary"}
```

`note` is trimmed and limited to 500 characters. Search matches note or
category name. Filters combine with AND. Results order by date, created time,
then ID descending.

## Summary API

`GET /api/v1/summary/overview?period=this_month` uses half-open UTC month
boundaries. Response includes `total_income`, `total_expense`,
`net_cash_flow_available`, and nullable `net_cash_flow`. Net cash flow is
unavailable for empty or expense-only periods. `summary` and
`largest_category` contain expense categories only; income-only responses use
an empty breakdown and `largest_category: null`.

Summary response shape:

```json
{
  "status_code": 200,
  "message": "Summary fetched successfully",
  "data": {
    "total_income": 100.10,
    "total_expense": 25.05,
    "net_cash_flow_available": true,
    "net_cash_flow": 75.05,
    "period": "this_month",
    "summary": [],
    "largest_category": null
  }
}
```

State examples:

- Empty: `total_income: 0`, `total_expense: 0`,
  `net_cash_flow_available: false`, `net_cash_flow: null`, empty `summary`,
  `largest_category: null`.
- Expense-only: income `0`, expense total present,
  `net_cash_flow_available: false`, `net_cash_flow: null`, expense breakdown
  present.
- Income-only: income total present, expense `0`,
  `net_cash_flow_available: true`, net equals income, empty breakdown,
  `largest_category: null`.
- Full: both totals present, `net_cash_flow_available: true`, net equals
  income minus expense, expense breakdown present.

Money totals use PostgreSQL `numeric` aggregation. API emits JSON numbers;
clients should parse them as decimal money values, not binary floating-point
values. This endpoint does not claim fixed trailing-zero formatting.

## Category lifecycle

- `GET /api/v1/categories`
- `POST /api/v1/categories` with `name`, `type`, optional `icon` and `color`
- `PUT /api/v1/categories/:id` with `name` to rename
- `PATCH /api/v1/categories/:id` with `status: "archived"` or `"active"`

Only categories owned by authenticated user can be changed. System categories
remain read-only. Category listing includes archived categories with
`status: "archived"`; archived categories retain historical transactions but
cannot receive new assignments.

## Comparison API

All comparison endpoints require JWT and use UTC half-open ranges:

- `GET /api/v1/summary/comparison?period=this_month`
- `GET /api/v1/summary/comparison/categories?period=this_month`
- `GET /api/v1/categories/:id/comparison?period=this_month`

`period` accepts `this_month` or `previous_month`. Response includes `periods`
with full ISO ranges for current and previous periods. Categories match by
persistent ID, retain current name, and drivers return at most three entries,
sorted by absolute change magnitude then category ID. Foreign category IDs
return `404`.

## Health check

### `GET /`

Checks API process and Neon DB connection.

Response `200`:

```json
{
  "status_code": 200,
  "message": "ClariMoney backend active",
  "data": {
    "db": "connected"
  }
}
```

## Auth API

### Session and token policy

- Access JWTs expire after 15 minutes and include session ownership binding.
- Access JWTs issued before session rollout lack `sid` and are invalid after
  deployment. Clients must sign in again.
- Refresh tokens expire 7 days after login. Each successful refresh rotates the
  token but keeps the original session expiry (fixed expiry).
- Reusing any consumed refresh token is intentional token-theft protection: the
  entire owning session is revoked, and the request returns `401`.
- `POST /api/v1/auth/logout` and `POST /api/v1/auth/logout-all` accept repeated
  requests with structurally valid, signed tokens. Expired access tokens remain
  rejected, preserving authentication safety; clients must retry before access
  token expiry or use a fresh authenticated token.

### `POST /api/v1/auth/register`

Request:

```json
{
  "email": "user@example.com",
  "password": "password123",
  "device_id": "mobile-device-uuid",
  "device_name": "Pixel 9"
}
```

Success `201`:

```json
{
  "status_code": 201,
  "message": "Registration successful",
  "data": {
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "email_verified": false
    },
    "access_token": "jwt",
    "refresh_token": "opaque-refresh-token",
    "session_id": "session-uuid",
    "token": "jwt"
  }
}
```

Validation:

- Email valid.
- Password minimum 8 characters.
- `device_id` required, non-empty, maximum 255 characters.
- Validation counts Dart UTF-16 code units; Unicode supplementary characters
  count as two units. Database `VARCHAR(255)` uses character semantics, so
  clients should keep device IDs within 255 UTF-16 code units.
- `device_name` optional.
- Email duplicate returns `409`.
- Missing or invalid `device_id` returns `400`:

```json
{
  "status_code": 400,
  "message": "device_id must be a non-empty string of 255 characters or fewer",
  "data": null
}
```
- Non-string `device_name` returns `400`:

```json
{
  "status_code": 400,
  "message": "device_name must be a string",
  "data": null
}
```

### `POST /api/v1/auth/login`

Request:

```json
{
  "email": "user@example.com",
  "password": "password123",
  "device_id": "mobile-device-uuid",
  "device_name": "Pixel 9"
}
```

Success `200`:

```json
{
  "status_code": 200,
  "message": "Login successful",
  "data": {
    "user": {
      "id": "uuid",
      "email": "user@example.com"
    },
    "access_token": "jwt",
    "refresh_token": "opaque-refresh-token",
    "session_id": "session-uuid",
    "token": "jwt"
  }
}
```

Invalid credentials return `401`:

```json
{
  "status_code": 401,
  "message": "Invalid email or password",
  "data": null
}
```

Missing or invalid `device_id` returns `400` with message
`device_id must be a non-empty string of 255 characters or fewer`.
Non-string `device_name` returns `400` with message
`device_name must be a string`.

### `GET /api/v1/auth/me`

Requires JWT. Returns current profile state:

```json
{
  "status_code": 200,
  "message": "Profile fetched successfully",
  "data": {
    "id": "uuid",
    "email": "user@example.com",
    "email_verified": false
  }
}
```

### `DELETE /api/v1/auth/account`

Requires JWT. Permanently deletes current account after verifying current
password. Deletion is irreversible. Foreign-key cascades remove categories,
transactions, sessions, and auth tokens.

Request:

```json
{ "password": "password123" }
```

Success `200` is returned only after deletion commits:

```json
{
  "status_code": 200,
  "message": "Account deleted successfully"
}
```

Missing or incorrect password returns `401` without deleting account data.

### `POST /api/v1/auth/resend-verification`

Requires JWT. Sends a 24-hour verification link for unverified accounts.
Prior unused verification tokens become invalid. Verified accounts return the
same generic success response without sending mail.

Success `200`:

```json
{
  "status_code": 200,
  "message": "If email is unverified, verification instructions were sent",
  "data": null
}
```

For unverified accounts, missing or failed SMTP configuration returns `500`:

```json
{
  "status_code": 500,
  "message": "Verification email unavailable",
  "data": null
}
```

Verified accounts return success before SMTP validation and do not send mail.
For unverified accounts, token issuance and delivery run within one database
transaction. Invalid SMTP configuration is checked before token invalidation;
existing tokens remain valid when configuration is missing or invalid. SMTP send
failure or timeout rolls back token invalidation and issuance. SMTP delivery has
a 10-second timeout. SMTP cannot participate in
database commit: if mail delivery succeeds but database commit later fails,
delivered link may be unusable; resend then issues a replacement.

### `POST /api/v1/auth/verify-email`

Public. Request:

```json
{ "token": "opaque-verification-token" }
```

Success `200` marks email verified and consumes token:

```json
{
  "status_code": 200,
  "message": "Email verified successfully",
  "data": { "email_verified": true }
}
```

Invalid, expired, or reused token returns generic `400`:

```json
{
  "status_code": 400,
  "message": "Invalid or expired verification token",
  "data": null
}
```

SMTP configuration uses `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`,
`SMTP_PASSWORD`, `SMTP_FROM`, and `APP_BASE_URL`. `APP_BASE_URL` must be the
frontend base URL that serves `/verify-email` and `/reset-password`; it is not
the API URL unless frontend routes live there. Credentials stay outside
committed files. Gmail requires an App Password.

### `POST /api/v1/auth/forgot-password`

Public. Request:

```json
{ "email": "user@example.com" }
```

Always returns `200` with the same response, whether account exists:

```json
{
  "status_code": 200,
  "message": "If an account exists, password reset instructions were sent",
  "data": null
}
```

Existing accounts receive one 30-minute reset token. Prior unused reset tokens
become invalid. Invalid input, missing accounts, and email delivery failures
remain indistinguishable through this endpoint.

SMTP failure rolls back token invalidation and issuance. SMTP cannot participate
in database commit: if delivery succeeds but commit later fails, delivered link
may be unusable; another forgot-password request issues a replacement.

Forgot-password responses use a 250 ms minimum duration. Missing-user requests
also validate SMTP configuration and perform bounded SMTP connection/auth
preflight without sending mail. All SMTP work is capped at 10 seconds. Residual
network and connection timing can still differ; rate limiting is not implemented.

### `POST /api/v1/auth/reset-password`

Public. Request:

```json
{ "token": "opaque-reset-token", "password": "newpassword123" }
```

Password requires at least 8 characters. Successful reset consumes token once,
updates password hash, increments `token_version`, and revokes every active
session. Invalid, expired, reused, or weak-password requests return generic
`400`:

```json
{
  "status_code": 400,
  "message": "Invalid or expired password reset request",
  "data": null
}
```

## Categories API

### `GET /api/v1/categories`

Requires JWT.

Success `200`:

```json
{
  "status_code": 200,
  "message": "Categories fetched successfully",
  "data": [
    {
      "id": "uuid",
      "name": "Food",
      "icon": "restaurant",
      "color": "#FF7043",
      "type": "expense"
    }
  ]
}
```

Returns system categories and current-user categories.

### `POST /api/v1/categories`

Requires JWT.

Request:

```json
{
  "name": "Subscriptions",
  "icon": "subscriptions",
  "color": "#7E57C2",
  "type": "expense"
}
```

Success `201` returns created category. Duplicate name returns `409`:

```json
{
  "status_code": 409,
  "message": "Category already exists",
  "data": null
}
```

## Transactions API

### `GET /api/v1/transactions?page=1&limit=10`

Requires JWT.

Rules:

- Default page: `1`.
- Default limit: `10`.
- Maximum limit: `100`.
- Results sorted by date descending.

Success `200`:

```json
{
  "status_code": 200,
  "message": "Transactions fetched successfully",
  "data": [
    {
      "id": "uuid",
      "category_id": "uuid",
      "amount": 25000,
      "date": "2026-09-15T00:00:00.000Z",
      "created_at": "2026-09-15T08:00:00.000Z",
      "category": {
        "name": "Food",
        "color": "#FF7043",
        "icon": "restaurant"
      }
    }
  ],
  "page": 1,
  "limit": 10,
  "total": 1,
  "total_pages": 1,
  "has_next": false
}
```

### `POST /api/v1/transactions`

Requires JWT.

Request:

```json
{
  "category_id": "category-uuid",
  "amount": 25000,
  "date": "2026-09-15T00:00:00.000Z"
}
```

Validation:

- `category_id` required.
- `amount` must be greater than zero.
- `date` must be valid ISO-8601.
- Category must be system-owned or owned by current user.

Success `201`:

```json
{
  "status_code": 201,
  "message": "Transaction created successfully",
  "data": {
    "id": "transaction-uuid"
  }
}
```

### `PUT /api/v1/transactions/:id`

Requires JWT. Updates only current-user transaction.

Request body matches transaction creation.

Success `200`:

```json
{
  "status_code": 200,
  "message": "Transaction updated successfully",
  "data": {
    "id": "transaction-uuid"
  }
}
```

Missing or foreign transaction returns `404`.

### `DELETE /api/v1/transactions/:id`

Requires JWT. Deletes only current-user transaction.

Success `200`:

```json
{
  "status_code": 200,
  "message": "Transaction deleted successfully",
  "data": null
}
```

## Summary API

### `GET /api/v1/summary/overview?period=this_month`

Requires JWT.

Accepted periods:

- `this_month`.
- `previous_month`.

Success `200`:

```json
{
  "status_code": 200,
  "message": "Summary fetched successfully",
  "data": {
    "total_expense": 250000,
    "period": "this_month",
    "summary": [
      {
        "category_id": "uuid",
        "name": "Food",
        "color": "#FF7043",
        "icon": "restaurant",
        "total": 150000,
        "percentage": 60
      }
    ],
    "largest_category": {
      "category_id": "uuid",
      "name": "Food",
      "total": 150000,
      "percentage": 60
    }
  }
}
```

## Common errors

| Status | Meaning |
|---:|---|
| `400` | Invalid request or validation failure |
| `401` | Missing or invalid JWT |
| `404` | Resource not found or not owned |
| `405` | HTTP method unsupported |
| `409` | Duplicate resource |
| `500` | Internal database/server failure |

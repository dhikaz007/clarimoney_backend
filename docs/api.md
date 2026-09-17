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

Protected:

- Categories.
- Transactions.
- Summary.

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

### `POST /api/v1/auth/register`

Request:

```json
{
  "email": "user@example.com",
  "password": "password123"
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
      "email": "user@example.com"
    },
    "token": "jwt"
  }
}
```

Validation:

- Email valid.
- Password minimum 8 characters.
- Email duplicate returns `409`.

### `POST /api/v1/auth/login`

Request:

```json
{
  "email": "user@example.com",
  "password": "password123"
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
    "token": "jwt"
  }
}
```

Invalid credentials return `401`.

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

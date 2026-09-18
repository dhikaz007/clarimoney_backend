# ClariMoney Database

Database memakai Neon PostgreSQL.

## Connection

Backend membaca connection string dari environment:

```text
DATABASE_URL=postgresql://...
```

SSL wajib aktif melalui `sslmode=require`.

## Tables

### `users`

Menyimpan akun user dan password hash.

| Column | Type | Null | Default | Description |
|---|---|---:|---|---|
| `id` | `UUID` | No | - | Primary key user |
| `email` | `VARCHAR(255)` | No | - | Email unik user |
| `password_hash` | `VARCHAR(255)` | No | - | Salted SHA-512 crypt hash |
| `created_at` | `TIMESTAMPTZ` | Yes | `CURRENT_TIMESTAMP` | Waktu pembuatan akun |

Constraints:

- Primary key: `users_pkey` pada `id`.
- Unique: `users_email_key` pada `email`.

### `categories`

Menyimpan klasifikasi income/expense system atau milik user.

| Column | Type | Null | Default | Description |
|---|---|---:|---|---|
| `id` | `UUID` | No | - | Primary key category |
| `user_id` | `UUID` | Yes | - | `NULL` untuk system category |
| `name` | `VARCHAR(100)` | No | - | Nama category |
| `icon` | `VARCHAR(50)` | No | `default_icon` | Nama icon client |
| `color` | `VARCHAR(9)` | No | `#000000` | Warna format `#RRGGBB` |
| `type` | `VARCHAR(20)` | No | `expense` | `income` atau `expense` |
| `status` | `VARCHAR(20)` | No | `active` | `active` atau `archived` |
| `origin` | `VARCHAR(20)` | No | `user_created` | `system` atau `user_created` |
| `created_at` | `TIMESTAMPTZ` | Yes | `CURRENT_TIMESTAMP` | Waktu pembuatan category |

Constraints:

- Primary key: `categories_pkey` pada `id`.
- Foreign key: `user_id` → `users.id`, delete cascade.
- Check: `type` is `income` or `expense`.
- Check: name trimmed, 1–50 characters; status and origin valid.
- Unique expression index: `uq_categories_owner_name_type`.
- Duplicate name dicegah case-insensitive per owner/type.

### `transactions`

Menyimpan income atau expense user.

| Column | Type | Null | Default | Description |
|---|---|---:|---|---|
| `id` | `UUID` | No | - | Primary key transaction |
| `user_id` | `UUID` | No | - | Pemilik transaction |
| `category_id` | `UUID` | No | - | Required income/expense category |
| `type` | `VARCHAR(20)` | No | `expense` | Transaction type |
| `amount` | `NUMERIC(15,2)` | No | - | Nominal expense |
| `date` | `TIMESTAMPTZ` | No | - | Tanggal expense; legacy wall-clock values normalized as UTC |
| `note` | `VARCHAR(500)` | Yes | - | Catatan trimmed |
| `created_at` | `TIMESTAMPTZ` | Yes | `CURRENT_TIMESTAMP` | Waktu pencatatan |

Constraints:

- Primary key: `transactions_pkey` pada `id`.
- Foreign key: `user_id` → `users.id`, delete cascade.
- Foreign key: `category_id` → `categories.id`; category hard delete is unsupported.
- Check: `amount > 0`.
- Check: category type matches transaction type; archived categories cannot receive new assignments.
- `category_id` is required for every transaction after migration 010.

## Indexes

| Index | Table | Purpose |
|---|---|---|
| `idx_transactions_user_date` | `transactions` | Mempercepat history user berdasarkan date |
| `idx_transactions_user_type_date` | `transactions` | History by owner, type, date |
| `idx_transactions_category` | `transactions` | Category lookup |
| `idx_transactions_note_search` | `transactions` | Case-insensitive note search |
| `idx_categories_user` | `categories` | Mempercepat lookup category owner |
| `idx_categories_user_type_status` | `categories` | Category type/status lookup |
| `idx_categories_name_search` | `categories` | Case-insensitive category search |
| `uq_categories_owner_name_type` | `categories` | Mencegah duplicate category |

Search indexes use `lower(...)` B-tree expressions for equality and prefix
search paths. They do not accelerate arbitrary substring search. Add the
`pg_trgm` extension and trigram indexes only when substring search becomes a
measured requirement.

## Relationships

```text
users 1 ──── * categories
users 1 ──── * transactions
categories 1 ──── * transactions
```

Delete behavior:

- Hapus user → categories dan transactions milik user ikut terhapus.
- Archive category instead of deleting it; historical transactions retain category references.

## Migration

Run numeric order:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/009_phase2_unified_transactions.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/010_phase2_unified_transactions_review_fixes.sql
```

Migration 010 applies legacy date conversion with `AT TIME ZONE 'UTC'`; API
dates remain full ISO-8601 timestamps with timezone and milliseconds where emitted.

`init_schema.sql` deprecated. Gunakan folder `migrations/`.

## Current Neon state

- Table `users`: active.
- Table `categories`: active, currently empty after test-data rollback.
- Table `transactions`: active, currently empty.
- Database: Neon PostgreSQL.

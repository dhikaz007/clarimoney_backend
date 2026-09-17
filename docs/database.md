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

Menyimpan klasifikasi expense system atau milik user.

| Column | Type | Null | Default | Description |
|---|---|---:|---|---|
| `id` | `UUID` | No | - | Primary key category |
| `user_id` | `UUID` | Yes | - | `NULL` untuk system category |
| `name` | `VARCHAR(100)` | No | - | Nama category |
| `icon` | `VARCHAR(50)` | No | `default_icon` | Nama icon client |
| `color` | `VARCHAR(9)` | No | `#000000` | Warna format `#RRGGBB` |
| `type` | `VARCHAR(20)` | No | - | MVP hanya `expense` |
| `created_at` | `TIMESTAMPTZ` | Yes | `CURRENT_TIMESTAMP` | Waktu pembuatan category |

Constraints:

- Primary key: `categories_pkey` pada `id`.
- Foreign key: `user_id` → `users.id`, delete cascade.
- Check: `type = 'expense'`.
- Unique expression index: `uq_categories_owner_name_type`.
- Duplicate name dicegah case-insensitive per owner/type.

### `transactions`

Menyimpan expense user.

| Column | Type | Null | Default | Description |
|---|---|---:|---|---|
| `id` | `UUID` | No | - | Primary key transaction |
| `user_id` | `UUID` | No | - | Pemilik transaction |
| `category_id` | `UUID` | Yes | - | Category expense |
| `amount` | `NUMERIC(15,2)` | No | - | Nominal expense |
| `date` | `TIMESTAMPTZ` | No | - | Tanggal expense |
| `created_at` | `TIMESTAMPTZ` | Yes | `CURRENT_TIMESTAMP` | Waktu pencatatan |

Constraints:

- Primary key: `transactions_pkey` pada `id`.
- Foreign key: `user_id` → `users.id`, delete cascade.
- Foreign key: `category_id` → `categories.id`, delete set null.
- Check: `amount > 0`.

## Indexes

| Index | Table | Purpose |
|---|---|---|
| `idx_transactions_user_date` | `transactions` | Mempercepat history user berdasarkan date |
| `idx_categories_user` | `categories` | Mempercepat lookup category owner |
| `uq_categories_owner_name_type` | `categories` | Mencegah duplicate category |

## Relationships

```text
users 1 ──── * categories
users 1 ──── * transactions
categories 1 ──── * transactions
```

Delete behavior:

- Hapus user → categories dan transactions milik user ikut terhapus.
- Hapus category → `transactions.category_id` menjadi `NULL`.

## Migration

Run numeric order:

```sh
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f migrations/002_mvp_constraints.sql
```

`init_schema.sql` deprecated. Gunakan folder `migrations/`.

## Current Neon state

- Table `users`: active.
- Table `categories`: active, currently empty after test-data rollback.
- Table `transactions`: active, currently empty.
- Database: Neon PostgreSQL.

#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  constraint_def text;
BEGIN
  IF to_regclass('public.auth_tokens') IS NULL THEN
    RAISE EXCEPTION 'public.auth_tokens table is missing; apply migrations 007 and 008';
  END IF;

  IF to_regclass('public.transactions') IS NULL OR to_regclass('public.categories') IS NULL THEN
    RAISE EXCEPTION 'transactions or categories table is missing; apply migrations 009 and 010';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users'
      AND column_name = 'email_verified_at'
  ) THEN
    RAISE EXCEPTION 'users.email_verified_at is missing';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'auth_tokens' AND column_name = 'id' AND data_type = 'uuid' AND is_nullable = 'NO')
  OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'auth_tokens' AND column_name = 'user_id' AND data_type = 'uuid' AND is_nullable = 'NO')
  OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'auth_tokens' AND column_name = 'token_hash' AND data_type = 'character varying' AND character_maximum_length = 64 AND is_nullable = 'NO')
  OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'auth_tokens' AND column_name = 'purpose' AND data_type = 'character varying' AND character_maximum_length = 32 AND is_nullable = 'NO')
  OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'auth_tokens' AND column_name = 'expires_at' AND data_type = 'timestamp with time zone' AND is_nullable = 'NO')
  OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'auth_tokens' AND column_name = 'used_at' AND data_type = 'timestamp with time zone' AND is_nullable = 'YES')
  OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'auth_tokens' AND column_name = 'created_at' AND data_type = 'timestamp with time zone' AND is_nullable = 'NO') THEN
    RAISE EXCEPTION 'auth_tokens columns, types, or nullability are incomplete';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_tokens'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%purpose%email_verification%password_reset%'
  ) THEN
    RAISE EXCEPTION 'auth_tokens purpose constraint is missing';
  END IF;

  SELECT pg_get_constraintdef(oid) INTO constraint_def
  FROM pg_constraint
  WHERE conrelid = 'public.auth_tokens'::regclass
    AND confrelid = 'public.users'::regclass
    AND contype = 'f'
    AND pg_get_constraintdef(oid) LIKE '%user_id%';
  IF constraint_def IS NULL OR constraint_def NOT LIKE '%ON DELETE CASCADE%' THEN
    RAISE EXCEPTION 'auth_tokens.user_id foreign key lacks ON DELETE CASCADE';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.auth_tokens'::regclass AND contype = 'u'
      AND pg_get_constraintdef(oid) = 'UNIQUE (token_hash)'
  ) THEN
    RAISE EXCEPTION 'auth_tokens.token_hash unique constraint is missing';
  END IF;

  IF to_regclass('public.idx_auth_tokens_user_purpose') IS NULL
     OR to_regclass('public.idx_auth_tokens_expiry') IS NULL THEN
    RAISE EXCEPTION 'required auth_tokens indexes are missing';
  END IF;

  IF to_regclass('public.idx_auth_tokens_hash') IS NOT NULL THEN
    RAISE EXCEPTION 'legacy idx_auth_tokens_hash remains; apply migration 008';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass AND attname = 'type' AND atttypid = 'pg_catalog.varchar'::regtype AND attnotnull)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass AND attname = 'category_id' AND attnotnull)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass AND attname = 'date' AND atttypid = 'pg_catalog.timestamptz'::regtype)
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.transactions'::regclass AND attname = 'note' AND atttypid = 'pg_catalog.varchar'::regtype AND atttypmod = 504) THEN
    RAISE EXCEPTION 'transactions phase 2 columns are incomplete';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.transactions'::regclass AND conname = 'transactions_category_id_fkey' AND contype = 'f' AND confrelid = 'public.categories'::regclass)
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.transactions'::regclass AND conname = 'transactions_amount_positive' AND pg_get_constraintdef(oid) LIKE '%amount >%0%')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.transactions'::regclass AND conname = 'transactions_type_check' AND pg_get_constraintdef(oid) LIKE '%income%expense%')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.transactions'::regclass AND conname = 'transactions_note_check' AND pg_get_constraintdef(oid) LIKE '%char_length%note%500%') THEN
    RAISE EXCEPTION 'transactions constraints are incomplete';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.categories'::regclass AND conname = 'categories_type_check' AND pg_get_constraintdef(oid) LIKE '%income%expense%')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.categories'::regclass AND conname = 'categories_status_check' AND pg_get_constraintdef(oid) LIKE '%active%archived%')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.categories'::regclass AND conname = 'categories_origin_check' AND pg_get_constraintdef(oid) LIKE '%system%' AND pg_get_constraintdef(oid) LIKE '%user_created%')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.categories'::regclass AND conname = 'categories_user_id_fkey' AND contype = 'f' AND confrelid = 'public.users'::regclass) THEN
    RAISE EXCEPTION 'category constraints are incomplete';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.transactions'::regclass AND tgname = 'transactions_category_compatibility' AND NOT tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.categories'::regclass AND tgname = 'categories_identity_mutation_guard' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'phase 2 compatibility triggers are missing';
  END IF;

  IF to_regclass('public.uq_categories_owner_name_type') IS NULL
     OR to_regclass('public.idx_transactions_user_type_date') IS NULL
     OR to_regclass('public.idx_transactions_category') IS NULL
     OR to_regclass('public.idx_transactions_note_search') IS NULL
     OR to_regclass('public.idx_categories_user_type_status') IS NULL
     OR to_regclass('public.idx_categories_name_search') IS NULL THEN
    RAISE EXCEPTION 'phase 2 indexes are incomplete';
  END IF;

  IF EXISTS (SELECT 1
    FROM (VALUES
      ('00000000-0000-0000-0000-000000000101'::uuid, 'Salary', 'salary', '#2E7D32'),
      ('00000000-0000-0000-0000-000000000102'::uuid, 'Bonus', 'bonus', '#388E3C'),
      ('00000000-0000-0000-0000-000000000103'::uuid, 'Freelance', 'freelance', '#43A047'),
      ('00000000-0000-0000-0000-000000000104'::uuid, 'Gift', 'gift', '#66BB6A'),
      ('00000000-0000-0000-0000-000000000105'::uuid, 'Other', 'other', '#81C784')
    ) AS expected(id, name, icon, color)
    LEFT JOIN public.categories c ON c.id = expected.id
      AND c.user_id IS NULL AND c.name = expected.name AND c.icon = expected.icon
      AND c.color = expected.color AND c.type = 'income'
      AND c.status = 'active' AND c.origin = 'system'
    WHERE c.id IS NULL) THEN
    RAISE EXCEPTION 'income starter categories are incomplete';
  END IF;
END $$;
SQL

printf '%s\n' 'Migration verification passed.'

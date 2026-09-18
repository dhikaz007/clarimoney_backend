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
END $$;
SQL

printf '%s\n' 'Migration verification passed.'

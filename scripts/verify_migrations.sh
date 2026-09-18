#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"

psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE
  constraint_def text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users'
      AND column_name = 'email_verified_at'
  ) THEN
    RAISE EXCEPTION 'users.email_verified_at is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'auth_tokens'
      AND column_name IN ('id', 'user_id', 'token_hash', 'purpose', 'expires_at', 'used_at', 'created_at')
    GROUP BY table_name
    HAVING COUNT(*) = 7
  ) THEN
    RAISE EXCEPTION 'auth_tokens columns are incomplete';
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

  IF to_regclass('public.idx_auth_tokens_hash') IS NOT NULL THEN
    RAISE EXCEPTION 'redundant idx_auth_tokens_hash still exists';
  END IF;
END $$;
SQL

printf '%s\n' 'Migration verification passed.'

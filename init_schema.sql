-- DEPRECATED: use migrations/001_initial_schema.sql through
-- migrations/010_phase2_unified_transactions_review_fixes.sql.
-- This legacy snapshot intentionally fails so fresh setup cannot create an
-- incompatible pre-Phase-2 schema.
DO $$ BEGIN
  RAISE EXCEPTION 'init_schema.sql is deprecated; run migrations/*.sql in order';
END $$;
/*
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE categories (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(100) NOT NULL,
  icon VARCHAR(50) NOT NULL DEFAULT 'default_icon',
  color VARCHAR(9) NOT NULL DEFAULT '#000000',
  type VARCHAR(20) NOT NULL CHECK (type IN ('income', 'expense')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE transactions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
  amount NUMERIC(15, 2) NOT NULL,
  date TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_date
  ON transactions (user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_categories_user
  ON categories (user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_categories_owner_name_type
  ON categories (COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name), type);
*/

-- Phase 2: unify income and expense transactions.

BEGIN;
SET LOCAL TIME ZONE 'UTC';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM transactions WHERE amount IS NULL OR amount <= 0) THEN
    RAISE EXCEPTION 'Migration 009 preflight failed: transactions contain NULL or non-positive amounts';
  END IF;
  IF EXISTS (
    SELECT 1 FROM categories
    WHERE name IS NULL OR btrim(name) = '' OR name <> btrim(name) OR char_length(btrim(name)) > 50
  ) THEN
    RAISE EXCEPTION 'Migration 009 preflight failed: categories contain blank, untrimmed, or overlong names';
  END IF;
END $$;

ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS type VARCHAR(20) NOT NULL DEFAULT 'expense',
  ADD COLUMN IF NOT EXISTS note VARCHAR(500);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'transactions'
      AND column_name = 'date'
      AND data_type = 'timestamp without time zone'
  ) THEN
    ALTER TABLE transactions
      ALTER COLUMN date TYPE TIMESTAMPTZ
      USING (date AT TIME ZONE 'UTC');
  END IF;
END $$;

UPDATE transactions SET type = 'expense' WHERE type IS NULL;

ALTER TABLE transactions
  ALTER COLUMN type SET DEFAULT 'expense',
  ALTER COLUMN type SET NOT NULL,
  DROP CONSTRAINT IF EXISTS transactions_type_check,
  DROP CONSTRAINT IF EXISTS transactions_note_check,
  ADD CONSTRAINT transactions_type_check CHECK (type IN ('income', 'expense')),
  ADD CONSTRAINT transactions_note_check CHECK (note IS NULL OR (note = btrim(note) AND char_length(note) <= 500)),
  DROP CONSTRAINT IF EXISTS transactions_amount_positive,
  ADD CONSTRAINT transactions_amount_positive CHECK (amount > 0);

ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS origin VARCHAR(20);

UPDATE categories
SET origin = CASE WHEN user_id IS NULL THEN 'system' ELSE 'user_created' END
WHERE origin IS NULL;

ALTER TABLE categories
  ALTER COLUMN origin SET DEFAULT 'user_created',
  ALTER COLUMN origin SET NOT NULL,
  DROP CONSTRAINT IF EXISTS categories_type_expense,
  DROP CONSTRAINT IF EXISTS categories_type_check,
  DROP CONSTRAINT IF EXISTS categories_name_check,
  DROP CONSTRAINT IF EXISTS categories_status_check,
  DROP CONSTRAINT IF EXISTS categories_origin_check,
  ADD CONSTRAINT categories_type_check CHECK (type IN ('income', 'expense')),
  ADD CONSTRAINT categories_name_check CHECK (name = btrim(name) AND char_length(name) BETWEEN 1 AND 50),
  ADD CONSTRAINT categories_status_check CHECK (status IN ('active', 'archived')),
  ADD CONSTRAINT categories_origin_check CHECK ((origin = 'system' AND user_id IS NULL) OR (origin = 'user_created' AND user_id IS NOT NULL));

DROP INDEX IF EXISTS uq_categories_owner_name_type;
CREATE UNIQUE INDEX IF NOT EXISTS uq_categories_owner_name_type
  ON categories (
    COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(name),
    type
  );

CREATE INDEX IF NOT EXISTS idx_transactions_user_type_date
  ON transactions (user_id, type, date DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_category
  ON transactions (category_id);
CREATE INDEX IF NOT EXISTS idx_transactions_note_search
  ON transactions (lower(note));
CREATE INDEX IF NOT EXISTS idx_categories_user_type_status
  ON categories (user_id, type, status);
CREATE INDEX IF NOT EXISTS idx_categories_name_search
  ON categories (lower(name));

CREATE OR REPLACE FUNCTION validate_transaction_category()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  category_type VARCHAR(20);
  category_status VARCHAR(20);
  category_user_id UUID;
BEGIN
  IF NEW.category_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT type, status, user_id INTO category_type, category_status, category_user_id
  FROM categories
  WHERE id = NEW.category_id;

  IF category_type IS NULL THEN
    RAISE EXCEPTION 'category does not exist';
  END IF;
  IF category_user_id IS NOT NULL AND category_user_id <> NEW.user_id THEN
    RAISE EXCEPTION 'category does not belong to transaction owner';
  END IF;
  IF category_type <> NEW.type THEN
    RAISE EXCEPTION 'category type must match transaction type';
  END IF;
  IF (TG_OP = 'INSERT' OR NEW.category_id IS DISTINCT FROM OLD.category_id) AND category_status <> 'active' THEN
    RAISE EXCEPTION 'archived category cannot be assigned';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS transactions_category_compatibility ON transactions;
CREATE TRIGGER transactions_category_compatibility
  BEFORE INSERT OR UPDATE OF type, category_id ON transactions
  FOR EACH ROW EXECUTE FUNCTION validate_transaction_category();

INSERT INTO categories (id, user_id, name, icon, color, type, status, origin)
VALUES
  ('00000000-0000-0000-0000-000000000101', NULL, 'Salary', 'salary', '#2E7D32', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000102', NULL, 'Bonus', 'bonus', '#388E3C', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000103', NULL, 'Freelance', 'freelance', '#43A047', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000104', NULL, 'Gift', 'gift', '#66BB6A', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000105', NULL, 'Other', 'other', '#81C784', 'income', 'active', 'system')
ON CONFLICT DO NOTHING;

COMMIT;

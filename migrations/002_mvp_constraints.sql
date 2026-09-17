ALTER TABLE transactions DROP COLUMN IF EXISTS note;

ALTER TABLE transactions
  DROP CONSTRAINT IF EXISTS transactions_amount_check;
ALTER TABLE transactions
  ADD CONSTRAINT transactions_amount_positive CHECK (amount > 0);

ALTER TABLE categories
  DROP CONSTRAINT IF EXISTS categories_type_check;
ALTER TABLE categories
  ADD CONSTRAINT categories_type_expense CHECK (type = 'expense');

CREATE INDEX IF NOT EXISTS idx_transactions_user_date
  ON transactions (user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_categories_user
  ON categories (user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_categories_owner_name_type
  ON categories (
    COALESCE(user_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(name),
    type
  );

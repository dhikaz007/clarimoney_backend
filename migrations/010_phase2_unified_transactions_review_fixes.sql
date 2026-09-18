-- Corrective follow-up for migration 009. Safe to rerun after 009.

BEGIN;
SET LOCAL TIME ZONE 'UTC';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM transactions WHERE amount <= 0 OR amount IS NULL) THEN
    RAISE EXCEPTION 'Migration 009 preflight failed: transactions contain non-positive or NULL amounts';
  END IF;
  IF EXISTS (
    SELECT 1 FROM categories
    WHERE name IS NULL OR btrim(name) = '' OR name <> btrim(name) OR char_length(btrim(name)) > 50
  ) THEN
    RAISE EXCEPTION 'Migration 009 preflight failed: categories contain blank, untrimmed, or overlong names';
  END IF;
END $$;

-- Preserve legacy timestamp wall-clock values as UTC, regardless of session timezone.
ALTER TABLE transactions
  ALTER COLUMN date TYPE TIMESTAMPTZ
  USING (date AT TIME ZONE 'UTC');

CREATE OR REPLACE FUNCTION prevent_category_identity_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF (NEW.type IS DISTINCT FROM OLD.type OR NEW.user_id IS DISTINCT FROM OLD.user_id)
     AND EXISTS (SELECT 1 FROM transactions WHERE category_id = OLD.id) THEN
    RAISE EXCEPTION 'category type or owner cannot change while transactions reference it';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS categories_identity_mutation_guard ON categories;
CREATE TRIGGER categories_identity_mutation_guard
  BEFORE UPDATE OF type, user_id ON categories
  FOR EACH ROW EXECUTE FUNCTION prevent_category_identity_mutation();

INSERT INTO categories (id, user_id, name, icon, color, type, status, origin)
VALUES
  ('00000000-0000-0000-0000-000000000101', NULL, 'Salary', 'salary', '#2E7D32', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000102', NULL, 'Bonus', 'bonus', '#388E3C', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000103', NULL, 'Freelance', 'freelance', '#43A047', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000104', NULL, 'Gift', 'gift', '#66BB6A', 'income', 'active', 'system'),
  ('00000000-0000-0000-0000-000000000105', NULL, 'Other', 'other', '#81C784', 'income', 'active', 'system')
ON CONFLICT (id) DO UPDATE SET
  user_id = EXCLUDED.user_id,
  name = EXCLUDED.name,
  icon = EXCLUDED.icon,
  color = EXCLUDED.color,
  type = EXCLUDED.type,
  status = EXCLUDED.status,
  origin = EXCLUDED.origin;

COMMIT;

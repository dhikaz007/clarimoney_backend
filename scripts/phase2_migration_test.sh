#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
migration="$root_dir/migrations/009_phase2_unified_transactions.sql"
corrective="$root_dir/migrations/010_phase2_unified_transactions_review_fixes.sql"

[[ -f "$migration" ]]
[[ -f "$corrective" ]]
sql=$(tr '[:upper:]' '[:lower:]' <"$migration")
corrective_sql=$(tr '[:upper:]' '[:lower:]' <"$corrective")

for required in \
  "raise exception 'migration 009 preflight failed" \
  "amount is null or amount <= 0" \
  "char_length(btrim(name))" \
  "using (date at time zone 'utc')"; do
  [[ "$sql" == *"$required"* ]] || { printf 'missing migration 009 sequencing: %s\n' "$required" >&2; exit 1; }
done

for required in \
  "alter table transactions" \
  "add column if not exists type" \
  "set default 'expense'" \
  "update transactions" \
  "add column if not exists note" \
  "alter table categories" \
  "add column if not exists status" \
  "add column if not exists origin" \
  "salary" "bonus" "freelance" "gift" "other" \
  "timestamptz" \
  "create index" \
  "trigger"; do
  [[ "$sql" == *"$required"* ]] || { printf 'missing SQL: %s\n' "$required" >&2; exit 1; }
done

for required in "category_id set not null" "transactions require categories"; do
  [[ "$corrective_sql" == *"$required"* ]] || { printf 'missing category requirement: %s\n' "$required" >&2; exit 1; }
done

for required in \
  'do $$' \
  "amount <= 0" \
  "char_length(btrim(name))" \
  "raise exception 'migration 009 preflight failed" \
  "at time zone 'utc'" \
  "information_schema.columns" \
  "timestamp without time zone" \
  "categories_identity_mutation_guard" \
  "on conflict (id) do update set" \
  "salary" "bonus" "freelance" "gift" "other" \
  "on conflict"; do
  [[ "$corrective_sql" == *"$required"* ]] || { printf 'missing corrective SQL: %s\n' "$required" >&2; exit 1; }
done

for required in \
  "equality and prefix" \
  "pg_trgm" \
  "010_phase2_unified_transactions_review_fixes.sql"; do
  grep -Fqi "$required" "$root_dir/migrations/README.md" "$root_dir/docs/database.md" || {
    printf 'missing documentation: %s\n' "$required" >&2; exit 1;
  }
done

printf '%s\n' 'Phase 2 migration contract tests passed.'

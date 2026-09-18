#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
migration="$root_dir/migrations/009_phase2_unified_transactions.sql"

[[ -f "$migration" ]]
sql=$(tr '[:upper:]' '[:lower:]' <"$migration")

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

printf '%s\n' 'Phase 2 migration contract tests passed.'

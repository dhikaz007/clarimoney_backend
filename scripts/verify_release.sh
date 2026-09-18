#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"
: "${JWT_SECRET:?JWT_SECRET is required}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
dart test >"$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
if grep -Eq '~[[:space:]]*[1-9][0-9]*([:]|[[:space:]]|$)' "$log"; then
  printf '%s\n' 'Release verification failed: tests skipped.' >&2
  exit 1
fi
if [[ -n ${DATABASE_URL:-} ]]; then
  ./scripts/verify_migrations.sh
fi

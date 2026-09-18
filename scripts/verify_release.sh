#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"
: "${JWT_SECRET:?JWT_SECRET is required}"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
dart test >"$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
if python3 - "$log" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
match = re.search(r'(\d+)\s+skipped', text)
raise SystemExit(0 if not match or int(match.group(1)) == 0 else 1)
PY
then
  :
else
  printf '%s\n' 'Release verification failed: tests skipped.' >&2
  exit 1
fi

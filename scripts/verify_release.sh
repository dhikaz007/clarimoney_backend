#!/usr/bin/env bash
set -euo pipefail
: "${RELEASE_VERIFY_DATABASE_URL:?RELEASE_VERIFY_DATABASE_URL is required; production DATABASE_URL is forbidden}"
: "${ALLOW_RELEASE_DB_MUTATION:?Set ALLOW_RELEASE_DB_MUTATION=true only for disposable release DB}"
if [[ "$ALLOW_RELEASE_DB_MUTATION" != true ]]; then
  printf '%s\n' 'Release verification refused: ALLOW_RELEASE_DB_MUTATION=true required for disposable database.' >&2
  exit 1
fi
normalize_db_url() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
u = urlsplit(sys.argv[1])
q = sorted((k, v) for k, v in parse_qsl(u.query) if k != 'channel_binding')
print(urlunsplit((u.scheme.lower(), u.netloc.lower(), u.path.rstrip('/'), urlencode(q), '')))
PY
}
release_url="$(normalize_db_url "$RELEASE_VERIFY_DATABASE_URL")"
if [[ -n "${DATABASE_URL:-}" ]] && [[ "$release_url" == "$(normalize_db_url "$DATABASE_URL")" ]]; then
  printf '%s\n' 'Release verification refused: disposable URL matches DATABASE_URL.' >&2
  exit 1
fi
release_host="$(python3 - "$RELEASE_VERIFY_DATABASE_URL" <<'PY'
import sys
from urllib.parse import urlsplit
print((urlsplit(sys.argv[1]).hostname or '').lower())
PY
)"
if [[ "$release_host" == *neon.tech || "$release_host" == *onrender.com || "$release_host" == *render.com ]] && [[ "${RELEASE_VERIFY_DISPOSABLE:-}" != true ]]; then
  printf '%s\n' 'Release verification refused: production-like host requires RELEASE_VERIFY_DISPOSABLE=true.' >&2
  exit 1
fi
export DATABASE_URL="$RELEASE_VERIFY_DATABASE_URL"
: "${JWT_SECRET:?JWT_SECRET is required}"
if [[ ${#JWT_SECRET} -lt 32 ]]; then
  printf '%s\n' 'Release verification refused: JWT_SECRET must contain at least 32 characters.' >&2
  exit 1
fi
if [[ "$DATABASE_URL" == *'channel_binding='* ]]; then
  DATABASE_URL="$(python3 - "$DATABASE_URL" <<'PY'
import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
url = urlsplit(sys.argv[1])
query = urlencode([(key, value) for key, value in parse_qsl(url.query) if key != 'channel_binding'])
print(urlunsplit((url.scheme, url.netloc, url.path, query, url.fragment)))
PY
)"
  export DATABASE_URL
fi
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f migrations/009_phase2_unified_transactions.sql
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f migrations/010_phase2_unified_transactions_review_fixes.sql
dart test >"$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
if grep -Eq '~[[:space:]]*[1-9][0-9]*([:]|[[:space:]]|$)' "$log"; then
  printf '%s\n' 'Release verification failed: tests skipped.' >&2
  exit 1
fi
./scripts/verify_migrations.sh

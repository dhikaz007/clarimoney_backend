#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bin_dir=$(mktemp -d)
trap 'rm -rf "$bin_dir"' EXIT

cat >"$bin_dir/dart" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${DART_TEST_OUTPUT:?DART_TEST_OUTPUT is required}"
SH
cat >"$bin_dir/psql" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$bin_dir/dart" "$bin_dir/psql"

run_case() {
  local name=$1 expected=$2 output=$3
  if DART_TEST_OUTPUT="$output" PATH="$bin_dir:$PATH" DATABASE_URL=test JWT_SECRET=test \
    bash "$script_dir/verify_release.sh" >/dev/null 2>&1; then
    actual=0
  else
    actual=1
  fi
  if [[ $actual -ne $expected ]]; then
    printf 'failed: %s\n' "$name" >&2
    exit 1
  fi
}

run_case 'compact one skipped' 1 '00:00 +0 ~1: test skipped'
run_case 'compact many skipped' 1 '00:00 +0 ~43: test skipped'
run_case 'spaced skipped' 1 '00:00 +0 ~ 1 skipped'
run_case 'zero skipped' 0 '00:00 +1: All tests passed!'

printf '%s\n' 'verify_release migration and skip parser tests passed.'

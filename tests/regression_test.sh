#!/usr/bin/env bash
# Negative regression cases: each snippet must fail during Genzimnify checking,
# before invalid Python reaches the runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

compiler="${GZIMC_BIN:-build/genzimc}"
if [ ! -x "$compiler" ]; then
  echo "$compiler is missing; run tests/run_tests.sh first" >&2
  exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/genzimnify-regression.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

pass=0
check_fails() {
  local name="$1" needle="$2" source="$3"
  local file="$tmp/$name.gzim"
  printf '%s\n' "$source" > "$file"
  if output="$("$compiler" check "$file" 2>&1)"; then
    echo "FAIL: $name unexpectedly passed"
    return 1
  fi
  if [[ "$output" != *"$needle"* ]]; then
    echo "FAIL: $name returned the wrong cap"
    echo "$output"
    return 1
  fi
  pass=$((pass + 1))
}

check_fails invalid_target "can't go on the left" '1 be 2'
check_fails try_without_handler "needs at least one" $'f_around:\n    yap("no handler")'
check_fails duplicate_param "duplicate param" $'cook nope(a, a):\n    deadass'
check_fails positional_after_keyword "positional arguments" 'call up thing(a be 1, 2) yo'
check_fails break_in_nested_cook "only works inside" $'vibe nocap:\n    cook nested():\n        dip\n    dip'
check_fails await_in_nested_sync "only works inside" $'on timing cook outer():\n    cook inner():\n        wait up task()'
check_fails fam_in_nested_cook "only makes sense" $'clique Vibe:\n    cook method(fam):\n        cook nested():\n            yap(fam)'
check_fails top_level_nonlocal "nested cook" 'localish x'

echo "$pass regression caps caught fr"

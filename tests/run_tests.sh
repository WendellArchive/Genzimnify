#!/usr/bin/env bash
# Genzimnify test suite: builds the native runtime, then runs each .gzim case
# and compares its output against the .expected file.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
test_bin="$(mktemp "${TMPDIR:-/tmp}/genzimc-test.XXXXXX")"
trap 'rm -f "$test_bin"' EXIT
echo "cooking the native runtime..."
nim c -d:release --verbosity:0 --hints:off \
  --nimcache:"${XDG_CACHE_HOME:-/tmp}/nim/genzimc_r" \
  -o:"$test_bin" src/gzim.nim || exit 1

pass=0
fail=0
for f in tests/cases/*.gzim; do
  exp="${f%.gzim}.expected"
  if actual="$("$test_bin" run "$f" 2>&1)" && [ "$actual" == "$(cat "$exp")" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL: $f"
    diff <(echo "$actual") "$exp" | head -20 || true
  fi
done

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  echo "that's cap, fix it"
  exit 1
fi
echo "all vibes check out fr"

GZIMC_BIN="$test_bin" bash tests/regression_test.sh
GZIM_NATIVE_BIN="$test_bin" bash tests/native_runtime_test.sh
GZIM_NATIVE_BIN="$test_bin" bash tests/package_manager_test.sh
python3 tests/package_manager_test.py "$test_bin"
python3 tests/runtime_correctness_test.py "$test_bin"
python3 tests/conversion_test.py "$test_bin"
python3 tests/cli_test.py "$test_bin"
python3 tests/rizzgame_test.py "$test_bin"

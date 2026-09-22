#!/usr/bin/env bash
# Genzimnify test suite: compiles the compiler, then runs each .gzim case
# and compares its output against the .expected file.
set -uo pipefail
cd "$(dirname "$0")/.."

mkdir -p build
echo "cooking the compiler..."
nim c -d:release --verbosity:0 --hints:off -o:build/genzimc src/genzimc.nim || exit 1

pass=0
fail=0
for f in tests/cases/*.gzim; do
  exp="${f%.gzim}.expected"
  actual="$(build/genzimc run "$f" 2>&1)"
  if [ "$actual" == "$(cat "$exp")" ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    echo "FAIL: $f"
    diff <(echo "$actual") "$exp" | head -20
  fi
done

echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  echo "that's cap — fix it"
  exit 1
fi
echo "all vibes check out fr"

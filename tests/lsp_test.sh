#!/usr/bin/env bash
# Runs the scripted LSP session test against the freshly built gzim-lsp.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
test_bin="$(mktemp "${TMPDIR:-/tmp}/gzim-lsp-test.XXXXXX")"
trap 'rm -f "$test_bin"' EXIT
nim c -d:release --verbosity:0 --hints:off \
  --nimcache:"${XDG_CACHE_HOME:-/tmp}/nim/gzimlsp_r" \
  -o:"$test_bin" src/gzimlsp.nim
GZIM_LSP_BIN="$test_bin" python3 tests/lsp_test.py > /dev/null
echo "lsp vibes check out fr"

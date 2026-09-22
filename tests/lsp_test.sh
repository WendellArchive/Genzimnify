#!/usr/bin/env bash
# Runs the scripted LSP session test against the freshly built gzim-lsp.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
nim c -d:release --verbosity:0 --hints:off -o:build/gzim-lsp src/gzimlsp.nim
python3 tests/lsp_test.py > /dev/null
echo "lsp vibes check out fr"

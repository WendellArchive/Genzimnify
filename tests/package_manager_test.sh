#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
runtime="${GZIM_NATIVE_BIN:-$repo_root/build/gzim}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/genzimnify-packages.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

cd "$tmp"
"$runtime" init >/dev/null
"$runtime" add cool "$repo_root/tests/packages/cool" >/dev/null
if [ ! -f gzim.lock ] || [[ "$(cat gzim.lock)" != *'"cool"'* ]]; then
  echo "package lockfile was not generated" >&2
  exit 1
fi
cp "$repo_root/tests/packages/app.gzim" main.gzim

actual="$("$runtime" main.gzim)"
if [ "$actual" != "$(cat "$repo_root/tests/packages/expected.txt")" ]; then
  echo "package manager integration output mismatch" >&2
  diff -u "$repo_root/tests/packages/expected.txt" <(printf '%s\n' "$actual")
  exit 1
fi

if [[ "$("$runtime" packages)" != *"cool"* ]]; then
  echo "installed package was not listed" >&2
  exit 1
fi
"$runtime" remove cool >/dev/null
if [ -d .gzim/packages/cool ]; then
  echo "removed package is still installed" >&2
  exit 1
fi

# A floating Git source must remain pinned to the commit in gzim.lock.
mkdir -p "$tmp/upstream"
cp "$repo_root/tests/packages/cool/cool.gzim" "$tmp/upstream/pinned.gzim"
git -C "$tmp/upstream" init -q
git -C "$tmp/upstream" add pinned.gzim
git -C "$tmp/upstream" -c user.name=Genzimnify -c user.email=test@example.invalid commit -qm first
"$runtime" add pinned "file://$tmp/upstream" >/dev/null
locked_revision="$(git -C .gzim/packages/pinned rev-parse HEAD)"
cp "$repo_root/tests/packages/cool_v2.gzim" "$tmp/upstream/pinned.gzim"
git -C "$tmp/upstream" add pinned.gzim
git -C "$tmp/upstream" -c user.name=Genzimnify -c user.email=test@example.invalid commit -qm second
"$runtime" install >/dev/null
restored_revision="$(git -C .gzim/packages/pinned rev-parse HEAD)"
if [ "$restored_revision" != "$locked_revision" ]; then
  echo "package lockfile did not pin the resolved Git commit" >&2
  exit 1
fi

# A failed update must preserve the manifest, lockfile, and installed package.
cp gzim.toml "$tmp/manifest-before"
cp gzim.lock "$tmp/lock-before"
if "$runtime" add pinned "file://$tmp/upstream#missing-revision" >/dev/null 2>&1; then
  echo "invalid package revision unexpectedly installed" >&2
  exit 1
fi
if ! cmp -s gzim.toml "$tmp/manifest-before" || ! cmp -s gzim.lock "$tmp/lock-before"; then
  echo "failed package update changed project metadata" >&2
  exit 1
fi
if [ "$(git -C .gzim/packages/pinned rev-parse HEAD)" != "$locked_revision" ]; then
  echo "failed package update replaced the working dependency" >&2
  exit 1
fi

echo "package manager integration passed"

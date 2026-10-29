#!/usr/bin/env sh
set -eu

REPOSITORY="Obliv1onis/Genzimnify"
INSTALL_ROOT="${GZIM_INSTALL_ROOT:-${XDG_BIN_HOME:-$HOME/.local/bin}}"
VERSION="${GZIM_VERSION:-latest}"

os="$(uname -s)"
arch="$(uname -m)"
case "$os-$arch" in
  Darwin-arm64) package="macos-arm64" ;;
  Darwin-x86_64)
    case "$VERSION" in
      v2.0.0|v2.0.1) package="macos-x86_64" ;;
      *) echo "Genzimnify 2.0.2 and newer require Apple Silicon on macOS." >&2; exit 1 ;;
    esac
    ;;
  Linux-x86_64|Linux-amd64) package="linux-x86_64" ;;
  *) echo "Genzimnify does not have a prebuilt binary for $os/$arch yet." >&2; exit 1 ;;
esac

if [ "$VERSION" = "latest" ]; then
  base_url="https://github.com/$REPOSITORY/releases/latest/download"
else
  base_url="https://github.com/$REPOSITORY/releases/download/$VERSION"
fi
archive_name="genzimnify-$package.tar.gz"
url="$base_url/$archive_name"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
echo "Downloading Genzimnify $VERSION for $package..."
curl -fsSL "$url" -o "$tmp_dir/genzimnify.tar.gz"
curl -fsSL "$base_url/SHA256SUMS" -o "$tmp_dir/SHA256SUMS"
expected="$(awk -v file="$archive_name" '$2 == file { print $1 }' "$tmp_dir/SHA256SUMS")"
if [ -z "$expected" ]; then echo "No checksum found for $archive_name." >&2; exit 1; fi
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp_dir/genzimnify.tar.gz" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "$tmp_dir/genzimnify.tar.gz" | awk '{print $1}')"
fi
if [ "$actual" != "$expected" ]; then echo "Checksum verification failed." >&2; exit 1; fi
tar -xzf "$tmp_dir/genzimnify.tar.gz" -C "$tmp_dir"
mkdir -p "$INSTALL_ROOT"
install -m 755 "$tmp_dir/gzim" "$INSTALL_ROOT/gzim"
install -m 755 "$tmp_dir/gzim-lsp" "$INSTALL_ROOT/gzim-lsp"
case "$package" in
  macos-arm64) game_library=libraylib.dylib ;;
  linux-x86_64) game_library=libraylib.so ;;
  *) game_library= ;;
esac
if [ -n "$game_library" ] && [ -f "$tmp_dir/$game_library" ]; then
  install -m 755 "$tmp_dir/$game_library" "$INSTALL_ROOT/$game_library"
fi

echo "Installed gzim and gzim-lsp to $INSTALL_ROOT"
case ":$PATH:" in
  *":$INSTALL_ROOT:"*) ;;
  *) echo "Add $INSTALL_ROOT to PATH, then run: gzim doctor" ;;
esac

#!/usr/bin/env bash
# Builds the AppSwap release browser and installer.
#
# Usage:
#   scripts/build.sh            # chrome + mini_installer
#   scripts/build.sh portable   # also package dist/AppSwap + zip
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src"
OUT="$SRC/out/Release"
PORTABLE="${1:-}"

# Stage the build args into the GN output directory.
mkdir -p "$OUT"
cp "$ROOT/build/args.gn" "$OUT/args.gn"

cd "$SRC"

echo "==> gn gen out/Release"
gn gen out/Release

echo "==> autoninja -C out/Release chrome mini_installer"
autoninja -C out/Release chrome mini_installer

if [[ "$PORTABLE" == "portable" ]]; then
  echo "==> packaging portable distribution"
  python tools/build/win/create_portable_archive.py \
    --build_dir out/Release \
    --output_dir "$ROOT/dist/AppSwap" \
    --chrome_release chrome/installer/mini_installer/chrome.release \
    --zip
fi

echo "Build complete."

#!/usr/bin/env bash
# Builds the AppSwap release browser (plus the Windows installer, on Windows).
#
# Usage:
#   scripts/build.sh            # chrome (+ mini_installer on Windows)
#   scripts/build.sh portable   # also package dist/AppSwap + zip (Windows only)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src"
OUT="$SRC/out/Release"
PORTABLE="${1:-}"

# args.gn has no target_os, so GN targets the host OS -- mini_installer and
# the portable packaging step only exist when that host is Windows.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
  *) IS_WINDOWS=0 ;;
esac

# Stage the build args into the GN output directory.
mkdir -p "$OUT"
cp "$ROOT/build/args.gn" "$OUT/args.gn"

cd "$SRC"

echo "==> gn gen out/Release"
gn gen out/Release

if [[ "$IS_WINDOWS" == "1" ]]; then
  echo "==> autoninja -C out/Release chrome mini_installer"
  autoninja -C out/Release chrome mini_installer
else
  echo "==> autoninja -C out/Release chrome"
  autoninja -C out/Release chrome
fi

if [[ "$PORTABLE" == "portable" ]]; then
  if [[ "$IS_WINDOWS" != "1" ]]; then
    echo "error: portable packaging is Windows-only (uses chrome/tools/build/win/create_portable_archive.py)" >&2
    exit 1
  fi
  echo "==> packaging portable distribution"
  python chrome/tools/build/win/create_portable_archive.py \
    --build_dir out/Release \
    --output_dir "$ROOT/dist/AppSwap" \
    --chrome_release chrome/installer/mini_installer/chrome.release \
    --zip
fi

echo "Build complete."

#!/usr/bin/env bash
# Switches the pinned Chromium revision and re-applies the patches.
#
# Usage: scripts/switch-chromium.sh <revision-hash>
#
# 1. Regenerates patches/ from the current working tree.
# 2. Pins the new revision in chromium_version.txt.
# 3. Syncs Chromium to the new revision (discarding local source changes).
# 4. Re-applies the patches.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW_REV="${1:-}"

if [[ -z "$NEW_REV" ]]; then
  echo "Usage: $0 <chromium-revision-hash>" >&2
  exit 1
fi

echo "1/4 Updating patches from current working tree..."
"$ROOT/scripts/update-patches.sh"

echo "2/4 Pinning $NEW_REV in chromium_version.txt..."
echo "$NEW_REV" > "$ROOT/chromium_version.txt"

echo "3/4 Resetting source tree and syncing Chromium to $NEW_REV ..."
git -C "$ROOT/src" reset --hard HEAD
git -C "$ROOT/src" clean -fd
"$ROOT/scripts/sync-chromium.sh"

echo "4/4 Applying patches..."
"$ROOT/scripts/apply-patches.sh"

echo "Done. Next step:"
echo "  scripts/build.sh   # or: .\\scripts\\build.ps1 (builds chrome + mini_installer)"

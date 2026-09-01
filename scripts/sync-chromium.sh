#!/usr/bin/env bash
# Fetches the exact Chromium revision pinned in chromium_version.txt.
#
# Requires depot_tools on PATH (gclient). Run from anywhere; it resolves the
# repo root relative to this script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REV="$(awk 'NF { print $1; exit }' "$ROOT/chromium_version.txt")"

if [[ -z "$REV" ]]; then
  echo "error: chromium_version.txt has no revision" >&2
  exit 1
fi

cd "$ROOT"

# Ensure a .gclient config exists (it is committed, but recreate defensively).
if [[ ! -f "$ROOT/.gclient" ]]; then
  gclient config --name src --unmanaged https://chromium.googlesource.com/chromium/src.git
fi

echo "Syncing Chromium to $REV ..."
gclient sync --no-history --nohooks --revision "src@$REV"
gclient runhooks
echo "Done: Chromium is now at $REV"

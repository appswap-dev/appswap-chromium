#!/usr/bin/env bash
# Applies all patches in patches/ (in sorted order) to src/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/src"

shopt -s nullglob
for patch in "$ROOT"/patches/*.patch; do
  echo "==> applying $(basename "$patch")"
  if ! git apply --3way --whitespace=nowarn "$patch"; then
    echo "error: failed to apply $(basename "$patch")" >&2
    exit 1
  fi
done

echo "All patches applied."

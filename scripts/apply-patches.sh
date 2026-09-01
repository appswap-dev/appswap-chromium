#!/usr/bin/env bash
# Applies all patches in patches/ (in sorted order) to src/ (or, for patches
# targeting nested DEPS checkouts that are their own git repos, to that
# checkout instead -- see the *devtools-frontend* case below).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

shopt -s nullglob
for patch in "$ROOT"/patches/*.patch; do
  name="$(basename "$patch")"
  echo "==> applying $name"
  case "$name" in
    *devtools-frontend*|*devtools-disable-paste-guard*)
      apply_dir="$ROOT/src/third_party/devtools-frontend/src"
      ;;
    *)
      apply_dir="$ROOT/src"
      ;;
  esac
  if ! git -C "$apply_dir" apply --3way --whitespace=nowarn "$patch"; then
    echo "error: failed to apply $name" >&2
    exit 1
  fi
done

echo "All patches applied."

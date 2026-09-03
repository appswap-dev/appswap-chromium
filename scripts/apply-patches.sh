#!/usr/bin/env bash
# Applies all patches in patches/ (in sorted order) to src/ (or, for patches
# targeting nested DEPS checkouts that are their own git repos, to that
# checkout instead -- see the *devtools-frontend* case below).
#
# src/ (and the nested devtools-frontend checkout) are reset to a clean,
# unpatched state first: apply-patches isn't idempotent against a tree that
# already has an old patch set applied (e.g. after pulling updated patches/
# from another machine), so re-applying on top of that fails. `git clean -fd`
# only removes untracked files that aren't gitignored -- out/ is gitignored
# (see src/.gitignore), so build output is left alone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Resetting src/ to a clean checkout..."
git -C "$ROOT/src" reset --hard HEAD
git -C "$ROOT/src" clean -fd

DEVTOOLS_DIR="$ROOT/src/third_party/devtools-frontend/src"
if [[ -d "$DEVTOOLS_DIR/.git" ]]; then
  echo "Resetting devtools-frontend checkout to a clean state..."
  git -C "$DEVTOOLS_DIR" reset --hard HEAD
  git -C "$DEVTOOLS_DIR" clean -fd
fi

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

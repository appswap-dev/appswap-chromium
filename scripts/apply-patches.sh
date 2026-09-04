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

# PROJECT_NAME (outer repo, not src/) tracks whatever name
# scripts/rename-project.py last renamed the product to -- reset it back to
# its committed value here too, so it stays in sync with src/'s branding
# text after a revert. rename-project.py reads this file to know what to
# search for, so leaving it stale would make the next rename silently find
# nothing to rename.
if git -C "$ROOT" cat-file -e HEAD:PROJECT_NAME 2>/dev/null; then
  git -C "$ROOT" checkout HEAD -- PROJECT_NAME
fi

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

# Binary icon assets (PNG/ICO/ICNS) live under resources/ as plain files,
# not as diffs in a *.patch -- see update-patches.sh's BINARY_RESOURCES for
# why. Restoring them is a plain copy, at the same relative path, over
# whatever git reset --hard just put back (vanilla Chromium's own icon, in
# every case here).
if [[ -d "$ROOT/resources" ]]; then
  echo "Restoring binary resources..."
  while IFS= read -r -d '' resource; do
    rel="${resource#"$ROOT/resources/"}"
    dest="$ROOT/src/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$resource" "$dest"
  done < <(find "$ROOT/resources" -type f -print0)
fi

echo "All patches applied."

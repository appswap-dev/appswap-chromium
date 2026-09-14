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

# The patches carry exact context from one specific Chromium revision -- the
# one pinned in chromium_version.txt. Against any other revision most hunks
# still land, but upstream churn silently breaks the rest, and src/ is a
# shallow (--no-history) checkout, so `git apply --3way` can't fall back to a
# real merge: it lacks the pre-image blobs and degrades to strict context
# matching. The result is a pile of per-hunk failures whose root cause (a
# tree that was never synced to the pinned rev) is nowhere in the output. So
# check the revision up front, before the reset below touches anything.
# Set APPSWAP_SKIP_VERSION_CHECK=1 to apply anyway, e.g. when deliberately
# rebasing the patch set onto a new revision with update-patches.sh.
VERSION_FILE="$ROOT/chromium_version.txt"
if [[ "${APPSWAP_SKIP_VERSION_CHECK:-0}" != "1" && -f "$VERSION_FILE" ]]; then
  pinned_line="$(awk 'NF { print; exit }' "$VERSION_FILE")"
  pinned_rev="${pinned_line%%[[:space:]]*}"
  pinned_desc=""
  if [[ "$pinned_line" == *"#"* ]]; then
    pinned_desc="$(printf '%s' "${pinned_line#*#}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  fi
  actual_rev="$(git -C "$ROOT/src" rev-parse HEAD 2>/dev/null || true)"
  if [[ -z "$actual_rev" ]]; then
    echo "error: $ROOT/src is not a git checkout -- run ./scripts/sync-chromium.sh first." >&2
    exit 1
  fi

  if [[ -n "$pinned_rev" && "$actual_rev" != "$pinned_rev" ]]; then
    actual_desc=""
    if [[ -f "$ROOT/src/chrome/VERSION" ]]; then
      actual_desc="$(awk -F= '{ v[$1] = $2 } END { print v["MAJOR"] "." v["MINOR"] "." v["BUILD"] "." v["PATCH"] }' "$ROOT/src/chrome/VERSION")"
    fi
    {
      echo "error: src/ is not at the Chromium revision these patches were made against."
      echo
      echo "  pinned (chromium_version.txt): $pinned_rev${pinned_desc:+  # $pinned_desc}"
      echo "  actual (src/ HEAD):            $actual_rev${actual_desc:+  # $actual_desc}"
      echo
      echo "Sync src/ to the pinned revision first:"
      echo "  ./scripts/sync-chromium.sh"
      echo
      echo "To apply against the current tree anyway (expect context failures):"
      echo "  APPSWAP_SKIP_VERSION_CHECK=1 ./scripts/apply-patches.sh"
    } >&2
    exit 1
  fi
fi

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

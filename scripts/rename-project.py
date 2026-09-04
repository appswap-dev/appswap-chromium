#!/usr/bin/env python3
"""Retextures the visible product name in src/'s translatable strings.

Replaces the literal word "AppSwap" with a new name across every .grd/.grdp/
.xtb file our patches currently touch -- i.e. every file that actually
carries "AppSwap" branding text at all. This only changes what users read
(message/translation content); it never touches BRANDING/PRODUCT_FULLNAME,
installer strings, C++ identifiers, directory names, or anything else tied
to the product's underlying identity.

This is a src/-only, ephemeral mutation -- it does NOT touch patches/*.patch.
To try a new name:

    python3 scripts/rename-project.py TestBrowser
    autoninja -C out/Release chrome   # or whatever your usual build step is

To go back to "AppSwap", just re-run apply-patches.sh -- it resets src/ to
HEAD and reapplies the unmodified patches, discarding this script's edits:

    bash scripts/apply-patches.sh

If you decide to keep a new name permanently, bake it into the patches
instead of reverting:

    bash scripts/update-patches.sh
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OLD_NAME = "AppSwap"

# Raw XML special characters would corrupt the files we're doing a literal
# substring replace into (these occurrences are always inside text nodes,
# never inside a quoted attribute -- see the rename-project skill notes /
# scripts/update-translations.py's own fingerprint work for why -- so we
# only need to guard against breaking the surrounding XML, not attribute
# quoting rules).
UNSAFE_CHARS = set('<>&"\'')


def find_translation_files() -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(SRC), "diff", "--name-only", "HEAD", "--",
         "*.grd", "*.grdp", "*.xtb"],
        capture_output=True, encoding="utf-8", errors="replace", check=True,
    )
    return [SRC / line for line in result.stdout.splitlines() if line.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("new_name", help='New product name, e.g. "TestBrowser"')
    args = parser.parse_args()
    new_name = args.new_name

    if not new_name:
        print("error: new name must not be empty", file=sys.stderr)
        return 1
    bad = UNSAFE_CHARS & set(new_name)
    if bad:
        print(f"error: new name contains characters that would break XML: {sorted(bad)}",
              file=sys.stderr)
        return 1

    files = find_translation_files()
    if not files:
        print("No patch-tracked .grd/.grdp/.xtb files found under src/ -- "
              "did you run apply-patches.sh first?", file=sys.stderr)
        return 1

    changed_files = 0
    total_occurrences = 0
    for f in files:
        if not f.exists():
            continue
        data = f.read_bytes()
        count = data.count(OLD_NAME.encode("utf-8"))
        if count == 0:
            continue
        data = data.replace(OLD_NAME.encode("utf-8"), new_name.encode("utf-8"))
        f.write_bytes(data)
        changed_files += 1
        total_occurrences += count

    print(f"Replaced {total_occurrences} occurrence(s) of \"{OLD_NAME}\" with "
          f"\"{new_name}\" across {changed_files} file(s) under src/.")
    print()
    print("This only changed src/ -- patches/*.patch are untouched. Build and")
    print("test now; to go back to \"AppSwap\" afterward, run:")
    print()
    print("    bash scripts/apply-patches.sh")
    print()
    print("To keep this name permanently instead, run:")
    print()
    print("    bash scripts/update-patches.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())

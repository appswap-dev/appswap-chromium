#!/usr/bin/env python3
"""Retextures the visible product name in src/'s translatable strings.

Replaces the current product name (read from the PROJECT_NAME file at the
repo root, defaulting to "AppSwap" if that file doesn't exist yet) with a
new name across every .grd/.grdp/.xtb file our patches currently touch --
i.e. every file that actually carries product-name branding text at all.
This only changes what users read (message/translation content); it never
touches BRANDING/PRODUCT_FULLNAME, installer strings, C++ identifiers,
directory names, or anything else tied to the product's underlying
identity. PROJECT_NAME is updated to the new name afterward, so a second
rename (TestBrowser -> SomethingElse, say) works directly without needing
to revert first -- the script always renames from whatever PROJECT_NAME
currently says, not a hardcoded string.

Renaming an English message changes its grit fingerprint (see
update-translations.py's own module docstring for why -- fingerprints are
computed from message content, not a naive hash of the .grd's raw text).
Left alone, that would silently orphan every existing ru/es (etc.)
translation whose English source mentions the product name: grit would look
up the new fingerprint, find no matching <translation id="..."> in the xtb,
and fall back to showing the (now also renamed) English text instead of the
real translation. So this script also recomputes fingerprints for every
affected message before and after the rename, via the same real `grit xmb`
tool update-translations.py uses, and rewrites the matching
<translation id="..."> entries in every locale's .xtb to the new id --
keeping existing translations attached to their message through the rename.

This is a src/-only, ephemeral mutation -- it does NOT touch patches/*.patch.
To try a new name:

    python3 scripts/rename-project.py TestBrowser
    autoninja -C out/Release chrome   # or whatever your usual build step is

To go back to the committed name, just re-run apply-patches.sh -- it resets
src/ to HEAD and reapplies the unmodified patches, discarding this script's
edits, and also resets PROJECT_NAME back to its committed value:

    bash scripts/apply-patches.sh

If you decide to keep a new name permanently, bake it into the patches
instead of reverting (and commit the updated PROJECT_NAME alongside them):

    bash scripts/update-patches.sh
"""
import argparse
import importlib.util
import subprocess
import sys
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
PROJECT_NAME_FILE = ROOT / "PROJECT_NAME"
DEFAULT_NAME = "AppSwap"

# These occurrences are always inside message/translation text nodes, never
# inside a quoted attribute (verified: no <message name="..."> or
# <translation id="..."> anywhere embeds the literal word "AppSwap") -- so a
# raw literal substring replace is safe, we just need to guard against
# breaking the surrounding XML itself.
UNSAFE_CHARS = set('<>&"\'')


def load_update_translations():
    spec = importlib.util.spec_from_file_location(
        "update_translations", ROOT / "scripts" / "update-translations.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def find_files(*patterns) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(SRC), "diff", "--name-only", "HEAD", "--", *patterns],
        capture_output=True, encoding="utf-8", errors="replace", check=True,
    )
    return [SRC / line for line in result.stdout.splitlines() if line.strip()]


def read_current_name() -> str:
    if PROJECT_NAME_FILE.exists():
        name = PROJECT_NAME_FILE.read_text(encoding="utf-8").strip()
        if name:
            return name
    return DEFAULT_NAME


def collect_messages_mentioning(ut, grd_grdp_files: list[Path], substring: str,
                                 restrict_to: set[str] | None) -> dict:
    """{name: (desc, meaning, body)} for every message in the given
    .grd/.grdp files whose current body contains `substring` (or, if
    restrict_to is given, whose name is in that set instead -- used for the
    after-rename pass, where we already know which names we care about, and
    `substring` is ignored)."""
    out = {}
    for f in grd_grdp_files:
        if not f.exists():
            continue
        root = ET.fromstring(f.read_text(encoding="utf-8", errors="ignore"))
        for name, (desc, meaning, body) in ut.collect_messages(root).items():
            if name in out:
                continue
            if restrict_to is not None:
                if name in restrict_to:
                    out[name] = (desc, meaning, body)
            elif substring in body:
                out[name] = (desc, meaning, body)
    return out


def compute_fingerprints(ut, messages: dict) -> dict:
    """name -> fingerprint, computed in parallel via the real grit tool."""

    def one(item):
        name, (desc, meaning, body) = item
        cand = ut.Candidate(name=name, desc=desc, meaning=meaning, body=body,
                             source_file="", reason="")
        return name, ut.compute_fingerprint(cand)

    results = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        for name, fp in ex.map(one, messages.items()):
            results[name] = fp
    return results


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
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

    old_name = read_current_name()
    if new_name == old_name:
        print(f'error: new name is the same as the current name ("{old_name}", '
              f"per {PROJECT_NAME_FILE.name}) -- nothing to do", file=sys.stderr)
        return 1

    grd_grdp_files = find_files("*.grd", "*.grdp")
    xtb_files = find_files("*.xtb")
    all_files = grd_grdp_files + xtb_files
    if not all_files:
        print("No patch-tracked .grd/.grdp/.xtb files found under src/ -- "
              "did you run apply-patches.sh first?", file=sys.stderr)
        return 1

    ut = load_update_translations()

    print(f'Scanning messages that mention the current name ("{old_name}")...')
    affected_before = collect_messages_mentioning(ut, grd_grdp_files, old_name, restrict_to=None)
    print(f"  {len(affected_before)} message(s) found; computing their current fingerprints "
          f"(this shells out to grit per message, runs in parallel)...")
    old_fingerprints = compute_fingerprints(ut, affected_before)

    changed_files = 0
    total_occurrences = 0
    for f in all_files:
        if not f.exists():
            continue
        data = f.read_bytes()
        count = data.count(old_name.encode("utf-8"))
        if count == 0:
            continue
        data = data.replace(old_name.encode("utf-8"), new_name.encode("utf-8"))
        f.write_bytes(data)
        changed_files += 1
        total_occurrences += count

    if changed_files == 0:
        print(f'error: found 0 occurrences of "{old_name}" under src/ -- '
              f"{PROJECT_NAME_FILE.name} says that's the current name, but src/ "
              f"doesn't match it (did apply-patches.sh get run since the last "
              f"rename?). Nothing changed.", file=sys.stderr)
        return 1

    print("Recomputing fingerprints for the renamed messages...")
    affected_after = collect_messages_mentioning(
        ut, grd_grdp_files, new_name, restrict_to=set(old_fingerprints))
    new_fingerprints = compute_fingerprints(ut, affected_after)

    remaps = {}  # old fingerprint -> new fingerprint
    for name, old_fp in old_fingerprints.items():
        new_fp = new_fingerprints.get(name)
        if new_fp is not None and new_fp != old_fp:
            remaps[old_fp] = new_fp

    remapped_entries = 0
    if remaps:
        print(f"Remapping {len(remaps)} changed fingerprint(s) across existing "
              f"translations...")
        for f in xtb_files:
            if not f.exists():
                continue
            data = f.read_bytes()
            orig = data
            for old_fp, new_fp in remaps.items():
                pattern = f'<translation id="{old_fp}">'.encode("utf-8")
                if pattern in data:
                    data = data.replace(
                        pattern, f'<translation id="{new_fp}">'.encode("utf-8"))
                    remapped_entries += 1
            if data != orig:
                f.write_bytes(data)

    PROJECT_NAME_FILE.write_text(new_name + "\n", encoding="utf-8")

    print()
    print(f"Replaced {total_occurrences} occurrence(s) of \"{old_name}\" with "
          f"\"{new_name}\" across {changed_files} file(s) under src/.")
    print(f"Remapped {remapped_entries} existing translation entr{'y' if remapped_entries == 1 else 'ies'} "
          f"to their new fingerprint(s), keeping them attached to their message.")
    print(f"Updated {PROJECT_NAME_FILE.name} to \"{new_name}\" -- renaming again "
          f"will start from here, no need to revert first.")
    print()
    print("This only changed src/ -- patches/*.patch are untouched. Build and")
    print(f'test now; to go back to "{DEFAULT_NAME}" (or whatever name is last')
    print("committed) afterward, run:")
    print()
    print("    bash scripts/apply-patches.sh")
    print()
    print("To keep this name permanently instead, run:")
    print()
    print("    bash scripts/update-patches.sh")
    print("    git add PROJECT_NAME  # and commit it alongside the regenerated patches")
    return 0


if __name__ == "__main__":
    sys.exit(main())

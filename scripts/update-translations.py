#!/usr/bin/env python3
"""Finds AppSwap-specific strings (new, or whose English text was changed by
one of our own patches/*.patch files) that are missing a translation for one
of TRACKED_LOCALES, and writes translations back once supplied.

This deliberately does NOT touch vanilla Chromium's own strings -- those
already go through Google's real translation pipeline on every DEPS roll,
and re-translating them ourselves would just fight upstream. Only messages
whose name or English content was introduced/changed by a diff in patches/
are ours to translate.

Fingerprint correctness matters a lot here: grit computes each message's
XTB id from a whitespace-stripped, placeholder-substituted form of its
content (see tools/grit/grit/extern/tclib.py's GenerateId()/
GetPresentableContent()), not a naive hash of the raw XML text. Rather than
reimplementing that (easy to get subtly wrong, and silently produce ids
that never match what the real build expects), this script always computes
ids by handing a tiny synthetic single-message .grd to the real `grit xmb`
tool and reading back its answer -- ground truth, by construction.

Usage:
  update-translations.py scan  -o manifest.json
  update-translations.py write -i filled_manifest.json

`scan` writes a JSON manifest of candidate messages, each with its computed
fingerprint and which of TRACKED_LOCALES are missing a translation. Fill in
the "translations" field per locale (see the file for the exact shape) and
pass it to `write`, which validates that every <ph>/%N placeholder token in
the source also appears untouched in each translation before inserting it
into the right locale's .xtb.
"""
import argparse
import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from xml.sax.saxutils import escape as xml_escape
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
GRIT_PY = SRC / "tools" / "grit" / "grit.py"

TRACKED_LOCALES = ["ru", "es", "pt-BR", "de", "fr", "ja", "zh-CN"]

# When the same message name is declared more than once under different
# <if expr> branches (e.g. a chrome-for-testing variant vs the real one),
# branches whose expr mentions any of these are skipped, so we collect the
# definition that's actually active for a normal AppSwap build.
SKIP_IF_EXPR_CONTAINS = ("chrome_for_testing", "_is_chrome_for_testing_branded")


@dataclass
class Candidate:
    name: str
    desc: str
    meaning: str
    body: str  # inner XML (may contain <ph> sub-elements), as found in source
    source_file: str  # path relative to SRC, e.g. "chrome/app/chromium_strings.grd"
    reason: str  # "new" or "changed"


def inner_xml(elem: ET.Element) -> str:
    """Reconstructs an element's content (text + children incl. their own
    tags/attrs + tails) as it would appear between <message ...> and
    </message> -- i.e. everything except the message tag's own attributes."""
    # ET.tostring() on a non-root element already serializes its own .tail
    # text after the closing tag -- appending child.tail again here would
    # duplicate it (this was a real bug: for a <ph> followed by a long
    # sentence before the next tag, that sentence got doubled).
    parts = [xml_escape(elem.text or '')]
    for child in elem:
        parts.append(ET.tostring(child, encoding='unicode'))
    return ''.join(parts).strip()


def collect_messages(root: ET.Element) -> dict:
    """Walks the whole tree (a parsed .grd or .grdp document), returning
    {name: (desc, meaning, body)} for every translateable <message>,
    skipping <if> branches per SKIP_IF_EXPR_CONTAINS."""
    out = {}

    def walk(elem):
        for child in elem:
            tag = child.tag
            if tag == 'if':
                expr = child.get('expr', '')
                if any(bad in expr for bad in SKIP_IF_EXPR_CONTAINS):
                    continue
                walk(child)
            elif tag == 'message':
                if child.get('translateable') == 'false':
                    continue
                name = child.get('name')
                if not name:
                    continue
                out[name] = (child.get('desc', ''), child.get('meaning', ''), inner_xml(child))
            else:
                walk(child)

    walk(root)
    return out


def git_show(relpath: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(SRC), "show", f"HEAD:{relpath}"],
        capture_output=True, encoding='utf-8', errors='replace')
    if result.returncode != 0:
        return None  # file didn't exist at HEAD (newly added by a patch)
    return result.stdout


def find_candidates() -> list:
    """Compares pristine HEAD (src/'s own git repo, which apply-patches.sh
    resets to before applying patches uncommitted) against the current,
    patched working tree, for every .grd/.grdp file that differs -- this
    picks up the combined effect of every patch at once, via real XML
    parsing rather than fragile diff-hunk text reconstruction."""
    result = subprocess.run(
        ["git", "-C", str(SRC), "diff", "--name-only", "HEAD", "--",
         "*.grd", "*.grdp"],
        capture_output=True, encoding='utf-8', errors='replace', check=True)
    changed_files = [f for f in result.stdout.splitlines() if f]

    candidates = []
    for relpath in changed_files:
        new_path = SRC / relpath
        if not new_path.exists():
            continue  # deleted, not our concern here
        try:
            new_root = ET.fromstring(new_path.read_text(encoding='utf-8', errors='ignore'))
        except ET.ParseError as e:
            print(f"  ! failed to parse {relpath}: {e}")
            continue
        new_msgs = collect_messages(new_root)

        old_text = git_show(relpath)
        old_msgs = {}
        if old_text is not None:
            try:
                old_msgs = collect_messages(ET.fromstring(old_text))
            except ET.ParseError as e:
                print(f"  ! failed to parse pristine {relpath}: {e}")

        for name, (desc, meaning, body) in new_msgs.items():
            old = old_msgs.get(name)
            if old is None:
                reason = 'new'
            else:
                old_desc, old_meaning, old_body = old
                if old_meaning == meaning and old_body == body:
                    continue  # only desc (or nothing fingerprint-relevant) changed
                reason = 'changed'
            candidates.append(Candidate(
                name=name, desc=desc, meaning=meaning, body=body,
                source_file=relpath, reason=reason))
    return candidates


def find_translation_files(grd_relpath: str) -> dict:
    """Returns {locale: xtb_relpath_from_SRC} for the given file. If it's a
    top-level .grd with its own <translations><file lang=.../></translations>
    section, uses that directly. If it's a .grdp part file (no translations
    section of its own), finds the top-level .grd that includes it via
    <part file="basename"> and uses that one's mapping instead."""
    path = SRC / grd_relpath
    text = path.read_text(encoding='utf-8', errors='ignore')
    mapping = {}
    for fm in re.finditer(r'<file\s+path="([^"]+)"\s+lang="([^"]+)"\s*/>', text):
        xtb_path, lang = fm.groups()
        mapping[lang] = str((path.parent / xtb_path).relative_to(SRC))
    if mapping:
        return mapping

    # .grdp part file: find its parent top-level .grd. Parents are usually
    # in the same directory as the part file, or in chrome/app/ -- check
    # both rather than assuming one location.
    basename = Path(grd_relpath).name
    search_dirs = [path.parent, SRC / "chrome" / "app"]
    for search_dir in search_dirs:
        for candidate_grd in search_dir.glob("*.grd"):
            parent_text = candidate_grd.read_text(encoding='utf-8', errors='ignore')
            if f'<part file="{basename}"' in parent_text or f"<part file='{basename}'" in parent_text:
                return find_translation_files(str(candidate_grd.relative_to(SRC)))
    return {}


def build_synthetic_grd(cand: Candidate) -> str:
    meaning_attr = f' meaning="{xml_escape(cand.meaning, {chr(34): "&quot;"})}"' if cand.meaning else ''
    desc = xml_escape(cand.desc, {chr(34): '&quot;'})
    return f"""<?xml version='1.0' encoding='UTF-8'?>
<grit latest_public_release="0" current_release="1" source_lang_id="en" enc_check="möl">
  <release seq="1" allow_pseudo="false">
    <messages fallback_to_english="true">
      <message name="{cand.name}" desc="{desc}"{meaning_attr}>
        {cand.body}
      </message>
    </messages>
  </release>
</grit>
"""


def compute_fingerprint(cand: Candidate) -> int:
    with tempfile.TemporaryDirectory() as td:
        grd_path = Path(td) / "synthetic.grd"
        xmb_path = Path(td) / "out.xmb"
        grd_path.write_text(build_synthetic_grd(cand), encoding='utf-8')
        result = subprocess.run(
            [sys.executable, str(GRIT_PY), "-i", str(grd_path), "xmb", str(xmb_path)],
            cwd=str(SRC), capture_output=True, encoding='utf-8', errors='replace', timeout=30)
        if result.returncode != 0:
            raise RuntimeError(f"grit xmb failed for {cand.name}:\n{result.stderr}")
        xmb_text = xmb_path.read_text(encoding='utf-8')
        m = re.search(r'<msg[^>]*\bid="(\d+)"', xmb_text)
        if not m:
            raise RuntimeError(f"no id found in xmb output for {cand.name}:\n{xmb_text}")
        return int(m.group(1))


def existing_translation_ids(xtb_path: Path) -> set:
    if not xtb_path.exists():
        return set()
    text = xtb_path.read_text(encoding='utf-8', errors='ignore')
    return set(re.findall(r'<translation id="(\d+)">', text))


def extract_placeholder_tokens(text: str) -> set:
    tokens = set(re.findall(r'<ph name="([^"]+)">', text))
    tokens |= set(re.findall(r'%\d+|\$\d+', text))
    return tokens


def cmd_scan(args):
    print("Finding AppSwap-specific message candidates (pristine HEAD vs. patched working tree)...")
    candidates = find_candidates()
    print(f"  {len(candidates)} candidate message(s) found (new or content-changed)")

    manifest = []
    for cand in sorted(candidates, key=lambda c: c.name):
        try:
            fp = compute_fingerprint(cand)
        except RuntimeError as e:
            print(f"  ! {e}")
            continue

        xtb_map = find_translation_files(cand.source_file)
        if not xtb_map:
            print(f"  ! could not resolve translation files for {cand.source_file}, skipping {cand.name}")
            continue

        missing = []
        for locale in TRACKED_LOCALES:
            xtb_relpath = xtb_map.get(locale)
            if xtb_relpath is None:
                print(f"  ! locale {locale} has no <file> entry for {grd_relpath}")
                continue
            if str(fp) not in existing_translation_ids(SRC / xtb_relpath):
                missing.append(locale)

        if not missing:
            continue

        manifest.append({
            "name": cand.name,
            "reason": cand.reason,
            "source_file": cand.source_file,
            "desc": cand.desc,
            "meaning": cand.meaning,
            "content": cand.body,
            "placeholder_tokens": sorted(extract_placeholder_tokens(cand.body)),
            "fingerprint": fp,
            "xtb_files": {loc: xtb_map[loc] for loc in missing},
            "translations": {loc: "" for loc in missing},
        })

    out_path = Path(args.output)
    out_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f"Wrote {len(manifest)} candidate(s) needing translation to {out_path}")
    if manifest:
        locale_counts = {}
        for entry in manifest:
            for loc in entry["xtb_files"]:
                locale_counts[loc] = locale_counts.get(loc, 0) + 1
        print("  missing-translation counts by locale:", locale_counts)


def cmd_write(args):
    manifest = json.loads(Path(args.input).read_text(encoding='utf-8'))
    touched_files = {}  # xtb_relpath -> list of (id, text) to append

    errors = []
    for entry in manifest:
        source_tokens = set(entry["placeholder_tokens"])
        fp = entry["fingerprint"]
        for locale, xtb_relpath in entry["xtb_files"].items():
            translation = entry.get("translations", {}).get(locale, "").strip()
            if not translation:
                continue  # not filled in yet, skip silently
            trans_tokens = extract_placeholder_tokens(translation)
            if trans_tokens != source_tokens:
                errors.append(
                    f"{entry['name']} [{locale}]: placeholder mismatch -- "
                    f"source has {sorted(source_tokens)}, translation has {sorted(trans_tokens)}")
                continue
            touched_files.setdefault(xtb_relpath, []).append((fp, translation))

    if errors:
        print("Refusing to write -- placeholder validation failed:")
        for e in errors:
            print(f"  ! {e}")
        sys.exit(1)

    for xtb_relpath, entries in touched_files.items():
        xtb_path = SRC / xtb_relpath
        # newline='' on both read and write: these files are LF-only, and
        # Python's default text mode would otherwise translate \n -> \r\n
        # on write (Windows), turning every line into a diff and bloating
        # the patch by tens of thousands of lines for a handful of real
        # additions.
        text = xtb_path.read_text(encoding='utf-8', newline='')
        existing_ids = existing_translation_ids(xtb_path)
        new_entries = []
        seen = {}  # fp -> translation already queued this run (different message
                    # names can share identical English text, and therefore the
                    # same fingerprint -- write each id at most once per run)
        for fp, translation in entries:
            if str(fp) in existing_ids:
                continue  # already present (e.g. re-running write after a partial run)
            if fp in seen:
                if seen[fp] != translation:
                    print(f"  ! conflicting translations for shared fingerprint {fp} in "
                          f"{xtb_relpath}: {seen[fp]!r} vs {translation!r} -- keeping the first")
                continue
            seen[fp] = translation
            new_entries.append(f'<translation id="{fp}">{translation}</translation>')
        if not new_entries:
            continue
        insertion = "\n".join(new_entries) + "\n"
        if "</translationbundle>" not in text:
            print(f"  ! {xtb_relpath} has no </translationbundle>, skipping")
            continue
        text = text.replace("</translationbundle>", insertion + "</translationbundle>")
        xtb_path.write_text(text, encoding='utf-8', newline='')
        print(f"  wrote {len(new_entries)} translation(s) to {xtb_relpath}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p_scan = sub.add_parser("scan", help="Find candidate messages missing translations")
    p_scan.add_argument("-o", "--output", default="translation_manifest.json")
    p_scan.set_defaults(func=cmd_scan)

    p_write = sub.add_parser("write", help="Write filled-in translations back into .xtb files")
    p_write.add_argument("-i", "--input", required=True)
    p_write.set_defaults(func=cmd_write)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

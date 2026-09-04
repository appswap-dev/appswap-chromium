---
name: update-translations
description: Find AppSwap-specific strings missing a translation for a tracked locale, translate them, and land them as the dedicated i18n patch. Use when asked to add/update translations, add a new locale, or after patches change English UI strings.
---

# Maintaining AppSwap's translations

AppSwap only translates strings that are **its own** -- new, or whose
English text was changed by one of our own patches. Vanilla Chromium's
own strings already get real translations from Google's own pipeline on
every DEPS roll; re-translating those ourselves would just fight
upstream and get silently overwritten. `scripts/update-translations.py`
draws exactly that line automatically by diffing pristine `HEAD` (what
`src/`'s own git repo resets to before patches are applied) against the
current, patched working tree.

Tracked locales live in `TRACKED_LOCALES` at the top of that script:
`ru, es, pt-BR, de, fr, ja, zh-CN` at last count. Adding a locale means
adding it to that list -- see "Adding a new locale" below for the rest.

## Why fingerprints are computed the way they are

Grit computes each string's `.xtb` id from a whitespace-stripped,
placeholder-substituted form of its content (see
`third_party/devtools-frontend`-adjacent tooling at
`src/tools/grit/grit/extern/tclib.py`'s `GenerateId()` /
`GetPresentableContent()`), not a naive hash of the raw XML text.
Reimplementing that by hand is an easy way to silently produce ids that
never match what the real build expects. Instead, `compute_fingerprint()`
wraps the candidate message in a tiny synthetic single-message `.grd` and
runs the real `grit xmb` tool on it -- ground truth, by construction, and
validated at the time this script was built by reproducing an *existing*
shipped translation's id from scratch before trusting a computed one for
anything new. If you ever doubt a fingerprint, do the same: hand-build a
synthetic `.grd` with the exact message, run
`python3 tools/grit/grit.py -i synthetic.grd xmb out.xmb` from `src/`,
and compare against a real `.xtb` entry you can independently confirm.

## Workflow

1. **Scan.**
   ```bash
   cd src && python3 -X utf8 ../scripts/update-translations.py scan -o /path/to/manifest.json
   ```
   Prints candidate counts and a missing-translation count per locale.
   Run this from `src/` (or pass absolute paths) -- the script resolves
   `.grd`/`.xtb` paths relative to `SRC = ROOT/src`. Use `-X utf8` and
   redirect output to a file rather than relying on `run_in_background`'s
   own truncated capture across multiple tool-call boundaries; background
   runs of this script can take a few minutes for the full candidate set.

2. **Decide scope.** For a first pass on a new locale, translate
   everything the scan found missing. For touch-up passes (patches
   changed a handful of strings since the last full pass), the manifest
   is already scoped to exactly what's missing -- no separate filtering
   needed.

3. **Translate, in batches of ~40-50, writing directly to the manifest.**
   Reading the full manifest into the conversation and printing every
   translation in chat wastes context for no reader benefit -- instead,
   for each batch, write a small throwaway Python script (see the shape
   below) that sets `entry['translations'][locale]` for that batch's
   names and re-saves the manifest, and just run it. Report progress as
   a running count, not the translated text itself.

   ```python
   # -*- coding: utf-8 -*-
   import json
   MANIFEST_PATH = r"<path>"
   batch = {
       "IDS_SOME_STRING": "translated text",
       # ...
   }
   manifest = json.load(open(MANIFEST_PATH, encoding='utf-8'))
   for entry in manifest:
       if entry['name'] in batch:
           entry['translations']['<locale>'] = batch[entry['name']]
   json.dump(manifest, open(MANIFEST_PATH, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
   ```
   Run each batch script with `python3 -X utf8 batch.py` (Windows'
   default codepage is not UTF-8; without `-X utf8` non-ASCII
   translations can crash or get mangled on write).

   Translation conventions observed so far (ru; re-derive per language,
   don't assume these generalize):
   - The brand name "AppSwap" itself stays in Latin script, unchanged.
   - `<ph name="X">...</ph>` and bare `$1`/`%1$s`/`{COUNT}`-style tokens
     must appear in the translation **exactly as in the source**, same
     set, untouched content inside `<ph>` -- `write`'s validation step
     enforces this and will refuse to write on mismatch, but get it
     right the first time rather than relying on that as a retry loop.
   - `&amp;` accelerator-mnemonic markers are kept, repositioned before
     whichever word/letter makes sense in the target language (check a
     few existing entries in that locale's `.xtb` for the house
     convention rather than guessing).
   - ICU `{COUNT, plural, =0 {...} =1 {...} other {...}}` structures:
     keep the exact same selector set as the source (don't switch to a
     target language's own CLDR plural categories like `one`/`few`/`many`
     if the source only used explicit `=0`/`=1`/`other`) -- translate only
     the text inside each branch.
   - **The same English source string can appear under multiple
     different `IDS_` names** (e.g. several places just say "Your
     AppSwap"). Since the fingerprint is content-based, they *must* get
     the identical translation -- `write` detects and warns on
     conflicting translations for a shared fingerprint (keeping the
     first), so a conflict warning means go fix the inconsistent one,
     not something to ignore.

4. **Write.**
   ```bash
   cd src && python3 -X utf8 ../scripts/update-translations.py write -i /path/to/manifest.json
   ```
   Validates placeholders, dedupes by fingerprint (not just by name --
   see above), and inserts `<translation id="...">` entries into the
   right `.xtb` files, skipping ids already present (safe to re-run).
   Check the output for `placeholder mismatch` or `conflicting
   translations` lines before moving on.

5. **Verify before touching patches.**
   ```bash
   cd src && python3 -c "
   import xml.etree.ElementTree as ET
   for f in [/* touched .xtb paths, from write's own output */]:
       root = ET.parse(f).getroot()
       ids = [t.get('id') for t in root.findall('translation')]
       print(f, 'count:', len(ids), 'dupes:', len(ids) - len(set(ids)))
   "
   ```
   Well-formed XML and zero duplicate ids. If dupes show up, something
   in step 4 didn't dedupe correctly -- don't proceed to patches with a
   dirty file; `git checkout -- <file>` it back to clean and re-run
   `write` after fixing the root cause.

6. **Regenerate patches.**
   ```bash
   bash scripts/update-patches.sh
   ```
   Must report **zero** "uncovered changes" warnings. If a touched
   `.xtb` file is already claimed by an existing patch's `gen()` call
   (exact filename *or* a glob pattern -- `grep -n` the filename across
   `scripts/update-patches.sh` before assuming it's new territory), that
   patch will redundantly recapture your new translations too unless you
   either move ownership of that file to the i18n patch (see "Moving
   ownership" below) or exclude it from the other patch's glob. Skipping
   this check is exactly how a clean-looking `write` run turns into a
   patch with tens of thousands of spurious diff lines.

7. **Full clean-apply sanity check.**
   ```bash
   bash scripts/apply-patches.sh
   ```
   Confirms every patch (old and new) still applies together with no
   conflicts, from a pristine reset. Re-run the well-formed/no-dupes
   check from step 5 after this, since it's the closest thing to what a
   fresh checkout will actually see.

## Moving ownership of a file into the i18n patch

If `grep`-ing turns up an existing patch already covering a `.xtb` (or,
via a glob like `'components/strings/components_chromium_strings_*.xtb'`,
implicitly covering it for *every* locale at once):

- **Exact filename in another patch's `gen()` call** (e.g. a feature
  patch that happened to add a handful of translations alongside its
  own strings): remove that path from the other patch's file list
  entirely. Its existing translations will get picked up automatically
  by the i18n patch's own `gen()` call the next time you list that file
  there -- nothing needs to be manually copied.
- **Glob pattern in another patch** (typically the original branding
  patch, which globs every locale): add a
  `':(exclude)path/to/the_one_locale.xtb'` pathspec line right after the
  glob for that specific locale, and add a one-line comment explaining
  why. **Do this in the same change that adds the locale's content to
  the i18n patch** -- excluding a locale from a glob before the i18n
  patch actually covers it silently drops that locale's existing
  translations from every patch (confirmed the hard way; `update-patches.sh`
  will flag it immediately as "changed but not present in any patch" if
  you do exclude before cover, which is your signal something's out of
  order). Don't preemptively exclude locales you haven't actually
  generated translations for yet, even if you plan to soon.

## Known pitfalls already fixed in the script (don't reintroduce)

- **Windows subprocess encoding**: `subprocess.run(..., text=True)`
  decodes with the system codepage, not UTF-8, on Windows -- git's own
  output is UTF-8 and this silently corrupts/crashes on non-ASCII
  content. Always pass `encoding='utf-8', errors='replace'` explicitly
  to any new subprocess call this script makes.
- **Double-escaping `<ph>` content**: when reconstructing a message's
  inner XML from a parsed `ElementTree` element, `.text`/`.tail` are
  already *unescaped* -- dumping them raw into a freshly-built XML
  string (for the synthetic fingerprinting `.grd`) produces invalid XML
  for any text containing a bare `&`. Re-escape with
  `xml.sax.saxutils.escape()` before re-embedding.
- **`ET.tostring()` on a non-root element already includes that
  element's own `.tail`** in this codebase's Python version -- appending
  `.tail` again separately duplicates it. This produced a very
  convincing-looking "duplicated English text" false alarm (traced all
  the way to briefly suspecting a bug in the original branding patch)
  before the actual cause -- a bug in this script, not the source --
  was found.
- **CRLF on write**: `Path.write_text(text, encoding='utf-8')` on
  Windows translates `\n` -> `\r\n`. These `.xtb` files are LF-only;
  writing without `newline=''` turns *every* line into a diff and can
  bloat a patch by tens of thousands of lines for a handful of real
  additions. Always pass `newline=''` to both `read_text`/`write_text`
  when touching these files (Python 3.13+; this project's toolchain has
  it).
- **Fingerprint collisions within one `write` run**: different `IDS_`
  names can share identical English text and therefore identical
  fingerprints. Deduplicating only against what's *already in the file*
  (not against what this same run is about to add) writes the same
  `<translation id="...">` multiple times. `write`'s `seen` dict handles
  this -- don't remove it.

## Adding a new locale

1. Add the locale code to `TRACKED_LOCALES` in
   `scripts/update-translations.py`.
2. Run the full workflow above for that locale.
3. In step 6, follow "Moving ownership" for every file the scan touches
   that's already claimed elsewhere -- this is usually the same 2-3
   files every time (`chrome/app/resources/chromium_strings_<locale>.xtb`,
   `chrome/app/resources/generated_resources_<locale>.xtb`,
   `components/strings/components_chromium_strings_<locale>.xtb`), but
   grep to confirm rather than assuming the set is identical to last
   time -- a new feature patch touching strings since the last locale
   was added could have picked up a `.xtb` file too.

## Commit and push

Only when explicitly asked (standing project convention, not specific
to this skill). Stage the touched `patches/*.patch` files and
`scripts/update-translations.py` if it changed; don't stage
`scripts/__pycache__/` or unrelated pre-existing untracked files.

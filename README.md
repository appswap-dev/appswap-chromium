# AppSwap Browser

AppSwap is a Chromium-based browser for enterprise use. This repository holds
only the AppSwap-specific layer — the Chromium source tree itself is **not**
committed. All changes to Chromium are kept as patches, pinned to an exact
upstream revision. This keeps the repo small and makes a Chromium upgrade a
matter of re-applying patches against a new revision.

## Architecture

```
appswap/
├── chromium_version.txt   # pinned Chromium git revision (full 40-char hash)
├── .gclient               # gclient config (fetches src/)
├── .gitignore             # ignores src/, depot_tools/, dist/, out/, ...
├── build/
│   └── args.gn            # GN args for the release build
├── patches/               # AppSwap modifications, split by topic
│   ├── 0001-branding.patch
│   ├── 0002-binary-rename.patch
│   ├── 0003-install-branding.patch
│   └── 0004-portable-scheme-pak.patch
├── scripts/               # .sh (CI / Linux / Git Bash) + .ps1 (Windows)
└── src/                   # Chromium checkout (fetched, git-ignored)
```

- `src/` is a standard Chromium checkout managed by `gclient`, and is git-ignored.
- `patches/` contains every AppSwap modification, grouped by topic.
- `chromium_version.txt` pins the exact upstream commit everything builds against.

## Prerequisites

- **depot_tools** on `PATH` (`gclient`, `gn`, `autoninja`). If you don't have it
  yet:
  ```bash
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git depot_tools
  export PATH="$PWD/depot_tools:$PATH"   # add to your shell profile to persist
  ```
  `depot_tools/` at the repo root is git-ignored, so this is a safe place to
  put it.
- **Git for Windows** (provides Git Bash, which the `.ps1` wrappers call).
- **Python 3** (used by the portable packaging script).
- **Visual Studio 2022** with the "Desktop development with C++" workload,
  **plus the C++ ATL component** (`Microsoft.VisualStudio.Component.VC.ATL`) —
  not installed by default even with that workload, and Chromium needs it
  (`atldef.h` errors mean it's missing). Add it via the Visual Studio
  Installer, or:
  ```powershell
  & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vs_installer.exe" modify `
    --installPath "C:\Program Files\Microsoft Visual Studio\2022\Community" `
    --add Microsoft.VisualStudio.Component.VC.ATL --quiet --norestart
  ```
  (must be run elevated — `--quiet`/`--passive` require it).
- **The exact Windows SDK version this pin requires.** Chromium hardcodes a
  required SDK version in `src/build/vs_toolchain.py`'s `SDK_VERSION`
  constant — for the currently pinned revision that's **10.0.28000**, ahead of
  what the public VS Installer's release channel offers as of this writing
  (it tops out at 10.0.26100). Install it standalone:
  ```powershell
  winget install -e --id Microsoft.WindowsSDK.10.0.28000
  ```
  `gn gen` will fail with a path like `...\Windows Kits\10\include\10.0.28000.0\um`
  "does not exist" if it's missing. Check `SDK_VERSION` in `vs_toolchain.py`
  after switching Chromium versions — it can change.

### Windows-specific gotchas

- **`core.autocrlf` must be `false`.** Git for Windows defaults to
  `core.autocrlf=true`, which rewrites every text file's line endings to CRLF
  on checkout — including `patches/*.patch`. A CRLF-mangled patch file makes
  `git apply` reject *every* file in it with `patch does not apply`, even
  though the content is otherwise byte-identical (diffing with
  `git diff --ignore-space-at-eol` shows no real change). Fix it once,
  globally, before cloning or syncing anything:
  ```bash
  git config --global core.autocrlf false
  git config --global core.filemode false
  git config --global core.fscache true
  git config --global core.preloadindex true
  ```
  If you already cloned this repo with `core.autocrlf=true` in effect, the
  files on disk are already CRLF-corrupted even after fixing the setting —
  `git checkout -- .` (after fixing the setting) re-checks them out cleanly,
  since the fix only changes *future* checkouts. Verify with
  `git diff --ignore-space-at-eol --stat` (should print nothing).
- Set `DEPOT_TOOLS_WIN_TOOLCHAIN=0` before running `sync-chromium.sh`/`.ps1`.
  Without it, `gclient runhooks` tries to fetch Google's internal (Googler-only)
  Visual Studio toolchain package instead of using your locally installed
  Visual Studio + Windows SDK.
- **Low RAM relative to core count causes misleading build failures.** If
  `autoninja` uses too much parallelism for the available memory, compiler
  processes fail to even start, and Windows reports it as
  `DLL Initialization Failed` (or a bare `NTSTATUS` code) — not a compile
  error, and easy to mistake for one. If you see a large batch of unrelated
  files fail at once, pass a lower `-j`, e.g.
  `autoninja -j 4 -C out/Release chrome mini_installer` (roughly 2-3GB of RAM
  per job is a safe budget).
- **`midl.exe output different from files in ...`** the first time you build:
  Chromium checks in a reference copy of MIDL-generated code under
  `third_party/win_build_output/midl/` to catch cross-toolchain drift, and it
  rarely matches a freshly-installed SDK's MIDL output exactly. This is
  expected, not a real error — follow the `copy /y ...` (or `cp -f ...`)
  command the build error itself prints, run from `src/out/Release` (paths in
  the error are relative to there, not your shell's cwd). It may need doing
  for more than one `.idl` target; passing `-k 0` to `autoninja` surfaces all
  of them in one pass instead of one at a time. This patches files inside
  `src/`, which is git-ignored, so it has to be redone after any fresh
  `sync-chromium.sh`.
- **Stale precompiled module cache after installing/upgrading a VC++ toolset
  component** (e.g. adding ATL mid-project, like above): you may see
  `precompiled file 'obj/build/modules/system/module.pcm' was compiled for
  target ... but the current translation unit is being compiled for target
  ...`. Fix by deleting the stale cache and regenerating the build graph:
  ```bash
  rm -rf src/out/Release/obj/build/modules
  cd src && gn gen out/Release
  ```

## Scripts

Each workflow step has a Bash script (for Git Bash / Linux CI) and a `.ps1`
alias that runs the Bash script from PowerShell:

| Action | Bash | PowerShell |
|--------|------|------------|
| Sync Chromium to the pinned revision | `scripts/sync-chromium.sh` | `.\scripts\sync-chromium.ps1` |
| Apply patches to `src/` | `scripts/apply-patches.sh` | `.\scripts\apply-patches.ps1` |
| Regenerate `patches/` from `src/` | `scripts/update-patches.sh` | `.\scripts\update-patches.ps1` |
| Switch Chromium version | `scripts/switch-chromium.sh <rev>` | `.\scripts\switch-chromium.ps1 <rev>` |
| Build release + installer | `scripts/build.sh [portable]` | `.\scripts\build.ps1 [-Portable]` |

## Quick start (fresh machine)

```bash
# 1. Fetch the exact Chromium revision and its dependencies
export DEPOT_TOOLS_WIN_TOOLCHAIN=0   # Windows only; see Prerequisites above
scripts/sync-chromium.sh

# 2. Apply the AppSwap patches
scripts/apply-patches.sh

# 3. Build the browser and installer
scripts/build.sh
```

On Windows PowerShell:

```powershell
$env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
.\scripts\sync-chromium.ps1
.\scripts\apply-patches.ps1
.\scripts\build.ps1
```

## Making a change

1. Edit files in `src/` (the Chromium checkout).
2. Regenerate the patches from your changes:
   ```bash
   scripts/update-patches.sh
   ```
3. `git status` this repo and commit the updated `patches/`.

`update-patches.sh` maps each changed file to its topic patch and warns about
any changed file that is not covered by a patch.

## Switching Chromium version

```bash
scripts/switch-chromium.sh <new-revision-hash>
```

This regenerates `patches/` from the current tree, pins the new revision in
`chromium_version.txt`, re-syncs Chromium, and re-applies the patches. Resolve
any `git apply` conflicts, then re-run `scripts/update-patches.sh`.

## Building

```bash
scripts/build.sh            # release browser + installer
scripts/build.sh portable   # + dist/AppSwap and dist/AppSwap.zip (portable)
```

Uses `build/args.gn` (`is_debug = false`, `is_component_build = false`,
`symbol_level = 0`). Outputs:

- `src/out/Release/appswap.exe`, `appswap.dll`, … — the release browser
- `src/out/Release/mini_installer.exe` — the installer
- `dist/AppSwap/` + `dist/AppSwap.zip` — portable distribution (`portable` only)

## The patches

| Patch | What it does |
|-------|--------------|
| `0001-branding.patch` | AppSwap product name, UI strings, and logos |
| `0002-binary-rename.patch` | Rename `chrome.*` binaries to `appswap.*` |
| `0003-install-branding.patch` | Install dir / registry / ProgID branding (`Chromium` → `AppSwap`) |
| `0004-portable-scheme-pak.patch` | Portable packaging script, `appswap://` scheme alias, `.pak` rename |

## Notes

- The portable ZIP does **not** preserve Windows ACLs. After unpacking on a new
  machine, launch via `dist\AppSwap\Launch AppSwap.cmd` (not `appswap.exe`
  directly) — it grants the AppContainer sandbox access the browser needs, then
  starts the browser.
- `src/`, `depot_tools/`, `dist/`, and `out/` are git-ignored.

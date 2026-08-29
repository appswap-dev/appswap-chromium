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

- **depot_tools** on `PATH` (`gclient`, `gn`, `autoninja`).
- **Git for Windows** (provides Git Bash, which the `.ps1` wrappers call).
- **Python 3** (used by the portable packaging script).
- A Chromium Windows build toolchain (Visual Studio + Windows SDK).

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
scripts/sync-chromium.sh

# 2. Apply the AppSwap patches
scripts/apply-patches.sh

# 3. Build the browser and installer
scripts/build.sh
```

On Windows PowerShell:

```powershell
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

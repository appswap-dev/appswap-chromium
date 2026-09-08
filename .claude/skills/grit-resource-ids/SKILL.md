---
name: grit-resource-ids
description: Add or edit a tools/gritsettings/resource_ids.spec entry, or wire up a new WebUI page's generated resources.grd/Lit build target/mojom. Use when adding a new chrome://-style WebUI page, when a build fails inside tools/grit/grit.py (e.g. "Cannot jump to unvisited: N"), when a new //chrome/browser/resources/*:build_ts target fails GN visibility, when a new WebUI page builds cleanly but navigating to it shows net::ERR_FAILED with no console/log output at all, when the mojom TS generator fails with "No WebUI bindings found for dependency", or when `gn gen` reports "Unresolved dependencies" on an auto-generated `*_js`/`*_js_data_deps` mojom subtarget.
---

# Working with grit: resource_ids.spec and new WebUI resource targets

Two real, confirmed-the-hard-way pitfalls live here, both hit while
wiring up `appswap://recordings` (a new WebUI page following the
`appswap://projects` template). Both fail at build time, not at
`gn gen` time for the visibility one's sibling errors, or specifically at
the `tools/grit/grit.py` siso rule for the resource-id one -- so the
error surfaces well after the code looks done and patches look clean.

## Pitfall 1: `resource_ids.spec` entries are NOT reserved numeric ranges

It is tempting to treat the `[####]` integers in
`tools/gritsettings/resource_ids.spec` as literal reserved id blocks and
place a new entry right after a similar feature's block ends (e.g.
`app_swap_projects` reserves `[2845, 2865)`, so a new entry "obviously"
goes at `2865`). **This is wrong and will break the build**, with an
error like:

```
File "...grit\tool\update_resource_ids\assigner.py", line 261, in GenStartIds
    raise ValueError('Cannot jump to unvisited: %d' % node.old_id)
ValueError: Cannot jump to unvisited: 2850
```

**Why**: per `tools/gritsettings/README.md`'s "Updating resource_ids.spec"
section (read it in full before touching this file -- the series-parallel
graph explanation is short and this skill only summarizes it), the
`[####]` values are **fake start IDs that encode ordering structure**,
not real reserved ranges. Real ids are computed later by
`grit update_resource_ids`, which walks entries in **file order** and
expects each entry's fake id to be consistent with a valid
series-parallel graph. Concretely: your new entry's fake id must be
**strictly between the fake ids of its immediate neighbors in file
order** -- not "after the previous entry's declared size", which can
easily exceed the *next* entry's fake id and break the graph (exactly
what happened above: `2865 > 2850`, the next entry in file order).

**The fix**: find where your new `.grd` belongs alphabetically within its
section (per the file's own header comment), look at the fake ids of the
entries immediately before and after that spot **in the file**, and pick
any integer strictly between them. Example: inserting between
`app_swap_projects` (`2845`) and the next entry (`2850`) -- valid choices
are `2846`-`2849`; this skill's own history used `2847`. If neighbors are
adjacent integers with no room ("crowded fake start IDs"), the README's
own "Special case: Crowded fake start IDs" section documents running
`grit update_resource_ids --fake` to make room -- don't hand-guess past
that point.

For a **generated** `.grd` (i.e. under `<(SHARED_INTERMEDIATE_DIR)/...`,
produced by `build_webui()` rather than checked into source) you also
need `"META": {"sizes": {"includes": [N]}}` giving an upper bound on how
many resources it'll define, since grit can't parse a file that doesn't
exist yet at spec-check time. `20` matches what `app_swap_projects` and
`app_swap_recordings` both used for a single-page Lit app; raise it if
grit later complains the bound was exceeded.

**Verification**: this can't be checked by reading the diff alone --
`grit update_resource_ids`'s ordering validation only runs as part of an
actual build (a siso/ninja rule invokes `tools/grit/grit.py`). There is
no lighter-weight standalone check to run instead; the real build step
is the only ground truth here.

## Pitfall 2: a new `//chrome/browser/resources/*:build_ts` Lit target needs an explicit visibility grant

`//third_party/lit/v3_0:build_ts` restricts its callers to an explicit
`visibility` allowlist in `third_party/lit/v3_0/BUILD.gn`. A new
`build_webui()` target using Lit (`ts_deps` including
`//third_party/lit/v3_0:build_ts`) that isn't in that list fails `gn gen`
with:

```
ERROR at //third_party/node/node.gni:9:3: Dependency not allowed.
The item //chrome/browser/resources/<your_page>:build_ts
can not depend on //third_party/lit/v3_0:build_ts
because it is not in //third_party/lit/v3_0:build_ts's visibility list: [...]
```

**The fix**: add
`"//chrome/browser/resources/<your_page>:build_ts"` to that `visibility`
list in `third_party/lit/v3_0/BUILD.gn`, alphabetically among the many
existing `//chrome/browser/resources/*:build_ts` entries (e.g. right next
to `app_swap_projects`/`app_swap_version_picker` for another
`app_swap_*` page). This file is already patch-tracked (added for
`app_swap_version_picker`) -- check `scripts/update-patches.sh` for which
`gen()` call owns it before adding a new one.

## Pitfall 3: a WebUI-facing mojom struct can't share a target with a native-only type that isn't itself WebUI-enabled

Hit while wiring up session-recording playback: a WebUI page's mojom
(`app_swap_recordings.mojom`, `webui_module_path = "/"`) needed to return a
struct (`FrameBitmap`) that was declared in a *different* mojom file
(`app_swap_playback.mojom`) alongside a native-only interface used only
between two C++ processes (`PlaybackRenderer`, browser <-> a child-process
service) -- and that interface's own struct (`LayerFrame`) used
`gfx.mojom.Transform`, a type with no WebUI/TS bindings configured. Putting
both in one `mojom()` target and giving it `webui_module_path` fails at
the TS-generation step:

```
AssertionError: No WebUI bindings found for dependency
<Module path='ui/gfx/mojom/transform.mojom' ...> imported by
<Module path='.../app_swap_playback.mojom' ...>
```

**Why**: `webui_module_path` on a `mojom()` target makes the TS generator
resolve *every* imported mojom into a JS module path -- including ones only
used by types the WebUI side never actually touches. If any of those
transitive imports lack WebUI bindings of their own (most low-level
`ui/gfx/mojom/*` types aren't WebUI-enabled), generation fails outright.

**The fix**: split into two mojom targets in the same `public/mojom/`
directory -- one `webui_module_path` target holding only the struct(s) the
WebUI genuinely needs (`FrameBitmap`, importing only WebUI-safe types like
`gfx.mojom.Size`), and a separate, plain target for the native-only
interface/structs (`PlaybackRenderer`/`LayerFrame`, free to import
`gfx.mojom.Transform` or anything else) that imports the first target for
whatever it shares.

That fix alone then trips a **second**, related error at `gn gen` time:

```
ERROR Unresolved dependencies.
//.../public/mojom:mojom_js(...) needs //.../public/mojom:bitmap_mojom_js(...)
```

**Why**: `mojom.gni`'s `webui_module_path` branch (`use_typescript_for_target`)
skips generating the classic `_js`/`_js_data_deps` groups for that target
entirely (TypeScript replaces them). But a *plain* mojom target that
depends on it still generates its own legacy `_js`/`_js_data_deps` groups
by default, and those unconditionally add a `<dep>_js` edge for every
dependency -- including the webui target, whose `_js` group doesn't exist.

**The fix**: add `cpp_only = true` to the plain (non-webui) target if
nothing ever needs JS/TS bindings for it specifically (true here --
`PlaybackRenderer`/`LayerFrame` only ever cross between two native
processes). That skips its own legacy-JS-group generation, which is also
what removes the dangling dependency on the other target's `_js` group.
This is the *correct* declaration of intent, not a workaround -- a mojom
interface with no JS/TS consumer anywhere should be `cpp_only` regardless
of this bug.

**Verification**: like Pitfall 1, this can't be checked by reading the
diff -- both errors only surface from the real mojom bindings generator
during a build (the first from `tools/bindings/mojom_bindings_generator.py`
under the `*_ts__generator`/`*_js__generator` actions, the second from
`gn gen` itself). Budget for it whenever a new mojom struct needs to be
shared between a WebUI page and a native-only interface that imports
lower-level (non-WebUI-enabled) mojom types.

**One more consequence of the split, a genuine C++ compile error, not a
build-config one**: once the struct lives in its own mojom file, any `.cc`
that actually *constructs, returns by value, or lets go out of scope* a
value of that struct's `*Ptr` type (e.g. `FrameBitmap::New()`, or even
just `some_callback.Run(nullptr)` for a callback whose parameter is that
`*Ptr` type) needs the struct's own generated header included directly --
```
error: invalid application of 'sizeof' to an incomplete type
'app_swap_playback::mojom::FrameBitmap'
... in defaulted destructor for 'mojo::StructPtr<...FrameBitmap>' ...
gen/.../app_swap_playback_bitmap.mojom-forward.h: forward declaration of
'app_swap_playback::mojom::FrameBitmap'
```
Just including the *other* mojom file's generated header (the one that
imports this struct) is not enough -- mojom generates a `-forward.h` for
an imported type and only forward-declares it in the importing file's own
`.h`, on the reasonable assumption that most uses only need a pointer/smart
pointer to it. `mojo::StructPtr<T>` (what a nullable struct field or
`*Ptr` typedef actually is) wraps a `std::unique_ptr<T>`, whose destructor
needs `T` complete -- so any `.cc` that owns a real value of that type,
even transiently (a `Run(nullptr)` temporary counts), needs
`#include ".../the_struct's_own_mojom.mojom.h"` directly, not just
whatever pulled the forward declaration in. This hits every `.cc` in the
call chain that touches the value, not just the one that originally
constructs it -- check all of them at once rather than fixing one,
rebuilding, hitting the next.

## Checklist: adding a new `appswap://<name>` WebUI page

Both pitfalls above surface specifically when doing this, so the full
checklist (verified against `appswap://projects` and
`appswap://recordings`, both real, working precedents to read directly
rather than re-deriving from scratch):

1. `chrome/browser/ui/webui/app_swap_<name>/`: `app_swap_<name>.mojom`,
   `app_swap_<name>_ui.h/.cc` (+ `*UIConfig` registered as
   `DefaultWebUIConfig(content::kChromeUIScheme, "appswap-<name>")`),
   `app_swap_<name>_page_handler.h/.cc`, `BUILD.gn` (a `mojom("mojo_bindings")`
   target plus a `source_set` depending on it).
2. `chrome/browser/resources/app_swap_<name>/`: `app.ts`/`app.html.ts`/
   `app.css` (a `CrLitElement`), `browser_proxy.ts` (the standard
   `PageHandlerFactory.getRemote()` + `getInstance()/setInstance()`
   wrapper), a static `app_swap_<name>.html` entry point, `BUILD.gn`
   (`build_webui()` with `grd_prefix = "app_swap_<name>"`).
3. Registration (four points, all required, all already patch-tracked by
   an existing `gen()` call for the `app_swap_projects` equivalent -- add
   your new page's files to that same call rather than creating a new
   one for these four):
   - `chrome/browser/ui/webui/chrome_web_ui_configs.cc`: include +
     `map.AddWebUIConfig(std::make_unique<AppSwap<Name>UIConfig>());`
   - `chrome/browser/chrome_browser_interface_binders_webui_parts_desktop.cc`:
     include + `RegisterWebUIControllerInterfaceBinder<
     app_swap_<name>::mojom::PageHandlerFactory, AppSwap<Name>UI>(map);`
   - `chrome/browser/ui/webui/BUILD.gn`: add
     `"//chrome/browser/ui/webui/app_swap_<name>"` to the `"configs"`
     source_set's deps (same list `chrome_web_ui_configs.cc` needs).
   - `tools/gritsettings/resource_ids.spec`: new entry -- see Pitfall 1
     above, don't guess a range-based value.
4. `third_party/lit/v3_0/BUILD.gn`: add the new page's `:build_ts` target
   to the `visibility` list -- see Pitfall 2 above.
5. `chrome/browser/browser_about_handler.cc`'s `HandleAppSwapURLRewrite()`:
   add a host special case so the short `appswap://<name>` alias actually
   resolves. This is easy to miss entirely -- it's not part of the
   WebUI/mojom/resources structure at all, it's separate scheme-routing
   plumbing from earlier work, and nothing about steps 1-4 fails if you
   skip it. Symptom if skipped: navigating to `appswap://<name>` silently
   becomes `chrome://<name>` (scheme swapped, host untouched) instead of
   `chrome://appswap-<name>`, and shows ERR_INVALID_URL -- no build error
   at all, since this is pure runtime URL-rewrite logic. Fix, mirroring
   the existing `"projects"` case in that function:
   ```cpp
   if (url->host() == "<name>") {
     replacements.SetHostStr("appswap-<name>");
   }
   ```
   Note this is one-directional by design: `ChromeContentBrowserClient::
   HandleWebUIReverse()` (chrome_content_browser_client.cc) does a plain
   scheme swap with no host-shortening, so after navigating, the omnibox
   displays the full `appswap://appswap-<name>`, not the short alias --
   matching how `appswap://projects` already behaves, not a bug to fix.
6. `chrome/chrome_paks.gni`: add
   `"$root_gen_dir/chrome/app_swap_<name>_resources.pak"` to the `sources`
   list under the `if (!is_android) { # New paks should be added here by
   default` comment, AND
   `"//chrome/browser/resources/app_swap_<name>:resources_grit"` to the
   matching `deps` list a bit further down (both already have the
   `app_swap_projects`/`app_swap_version_picker` equivalents right there
   to copy). **This is the worst one to miss**: everything else --
   `gn gen`, compilation, even the generated `chrome/grit/
   app_swap_<name>_resources.h`/`_map.cc` headers -- succeeds completely
   normally without it. The resources exist at build-graph level but
   never get bundled into the actual `resources.pak` the running browser
   loads, so at runtime the page's own main HTML document simply isn't
   found. Symptom: navigating to `chrome://appswap-<name>/` (URL already
   correct, steps 1-5 all done right) shows `net::ERR_FAILED` on the main
   document request -- with **zero output anywhere**: no C++ log line
   (checked with `--enable-logging=stderr`), no renderer console message,
   no crash. DevTools opened *after* the failure shows a blank Console
   and Network tab too, because by then you're inspecting Chrome's error
   interstitial, not the failed navigation -- you have to open DevTools
   with Network "Preserve log" turned on *before* navigating to actually
   catch the failing `chrome://appswap-<name>/` request and confirm this
   is what's happening (a red `ERR_FAILED` line on that exact URL, no
   response detail beyond that).

Steps 3-6 are the ones that don't fail until either an actual build runs
(`gn gen` catches step 4; the grit siso rule catches step 3's last
bullet) or, for steps 5-6, don't fail at all -- just silently misroute or
silently omit at runtime with no error pointing back at the missing code.
Budget for at least one build-and-fix iteration on a first pass at a new
page, same as any other genuinely new (not copy-pasted-and-proven) wiring
in this codebase.

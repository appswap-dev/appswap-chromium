# Plan: one reusable DevTools UI for Responsive Lab cells

**Status:** proposed, not started. Research done 2026-09-15 against Chromium
**155.0.8040.2** (`0a7a7e0199b7d1f1c455836e937363a65bf37047`), patches applied.

**Goal.** Responsive Lab shows N cells, each its own `WebContents`. Focus a cell
and a single, *real* DevTools UI retargets to it -- Elements, Console, Sources,
Network all following the focused cell. Reuse the DevTools frontend rather than
continuing to hand-roll an inspector.

**Why elsewhere:** a full build is ~8h on the author's Mac. Everything below is
written so a session on a faster machine can start cold.

---

## 1. Why this is worth doing

Patch `0017-responsive-lab.patch` already contains a bespoke partial DevTools:
`chrome/browser/app_swap/app_swap_responsive_lab_inspector.{h,cc}` does
cross-viewport element picking, per-viewport matched CSS rules, merged console,
and apply-style-to-all. It works, but every additional DevTools capability
(Sources, Network, breakpoints, profiling) means reimplementing DevTools.

The existing code documents why the DevTools route was skipped
(`app_swap_responsive_lab_viewport_client.h`):

> Deliberately a protocol client rather than a DevTools window: the DevTools
> frontend binds to exactly one primary page target, chosen for it at startup
> with no switcher, and each lab cell is its own WebContents and therefore its
> own target -- so one frontend can't span the grid.

**That premise is now believed wrong.** DevTools has a supported retargeting
mechanism. Section 2 is the evidence.

---

## 2. Key finding: `setScopeTarget`

`TargetManager` has a scope concept built for prerendering / multi-page tabs.
Its doc comment reads like a spec for this feature
(`src/third_party/devtools-frontend/src/front_end/core/sdk/TargetManager.ts:465`):

> TargetManager API invoked with `scoped: true` will behave as if targets
> outside of the scope subtree don't exist. [...] This method will invoke
> targetRemoved and modelRemoved for objects in the previous scope, as if they
> disappear and then will invoke targetAdded and modelAdded as if they just
> appeared.

`setScopeTarget()` (same file, line 473) tears down every scoped observer
against the old target and replays construction against the new one. Panels
need no changes -- they already handle targets coming and going.

It is **already wired to a UI context flavor**
(`front_end/entrypoints/main/MainImpl.ts:458`):

```js
targetManager.setScopeTarget(targetManager.primaryPageTarget());
UI.Context.Context.instance().addFlavorChangeListener(SDK.Target.Target, ({data}) => {
  const outermostTarget = data?.outermostTarget();
  targetManager.setScopeTarget(outermostTarget);
});
```

So on the frontend, "focus cell 3" is one call:

```js
UI.Context.Context.instance().setFlavor(SDK.Target.Target, cell3Target);
```

### Panel coverage (verified)

31 non-test files observe with `scoped: true`.

| Panel | Scoped? | Evidence |
|---|---|---|
| Elements | yes | `panels/elements/ElementsPanel.ts:322`, `:776` |
| Console | yes | `panels/console/ConsoleView.ts:652-662` (5 registrations) |
| Network | yes | `panels/network/NetworkPanel.ts:374`, `NetworkLogView.ts:726` |
| Security / Layers / Animation | yes | `SecurityPanel.ts:600`, `LayersPanel.ts:45`, `AnimationTimeline.ts:313` |
| **Sources** | **partial** | `SourcesPanel.ts:312` uses unscoped `observeTargets(this)` |

Sources is the one gap. `NavigatorView.ts:750` does respond to scope: the scope
target's files are promoted to the tree root and other targets are bucketed
under a `target:<id>` group node. Focused cell at root, other cells grouped
below -- acceptable, arguably desirable, but not literal isolation.

---

## 3. Getting N cells into one frontend

Needs real C++ work. There is a precedent to copy.

`DevToolsUIBindings::AttachViaBrowserTarget`
(`src/chrome/browser/devtools/devtools_ui_bindings.cc:3124`) attaches the
frontend to a **browser** target while recording an `initial_target_id_`:

```cpp
agent_host_ = content::DevToolsAgentHost::CreateForBrowser(
    nullptr /* tethering_task_runner */,
    content::DevToolsAgentHost::CreateServerSocketCallback());
initial_target_id_ = agent_host->GetId();
```

Its only existing caller is the dedicated-worker DevTools window
(`devtools_window.cc:678`). A browser-target session is what lets the frontend
see targets it does not own (`Target.getTargets` / `Target.attachToTarget`)
rather than being confined to one page subtree. `ChildTargetManager` already
drives auto-attach with `flatten: true`.

Intended shape: Responsive Lab opens **one** DevTools frontend attached via
browser target, attaches each cell's `WebContents` as a page target, and maps
cell focus to `setFlavor`.

### Confirmed constraint: no docking

`devtools_window.cc:1396-1409` resolves docking via
`GlobalBrowserCollection::FindBrowserWithTab(inspected_web_contents)`. A lab
cell is inside a `views::WebView` on the lab canvas, not a tab, so `browser` is
null and `can_dock = false`. The existing header comment is accurate.

Not fatal -- it means DevTools cannot dock to a tab. For Responsive Lab the UI
should be embedded in the lab panel or its own window anyway. **Decide the
host surface in Phase 1.**

---

## 4. Phase 0 -- spike first (do not skip)

Cheapest thing that invalidates the whole plan. Target: ~1 day, one build.

1. Attach two `WebContents` to a single DevTools frontend via browser target.
2. Toggle `UI.Context.Context.instance().setFlavor(SDK.Target.Target, t)`
   between them.
3. Confirm Elements and Console actually retarget.

**Exit criteria:** Elements tree and Console output both switch. If they do,
the rest is engineering. If they do not, stop and reassess -- do not start
Phase 1.

### Two risks this must settle

- **`primaryPageTarget()` under a browser-target root.** `MainImpl.ts:458`
  seeds scope from `primaryPageTarget()`, and `InspectorMain.ts:56` picks root
  target type from the `targetType` query param (`tab` vs `frame`). With N
  sibling page targets there is no single primary page, so seeding is
  ill-defined; seed explicitly from the focused cell.
  `TargetManager.ts:408` special-cases `Type.TAB` nearby -- read it closely.
- **`outermostTarget()` must resolve per cell.** The flavor listener calls
  `data?.outermostTarget()`, walking `parentTarget()`. Each cell must be its
  own outermost root, or focusing a cell scopes to a shared ancestor and
  retargeting silently fails to isolate.

---

## 5. Phases

**Phase 1 -- host surface.** Decide and build where the frontend lives
(embedded in the lab WebUI panel vs. separate window). Wire
`AttachViaBrowserTarget`-style attach for a lab session. Deliverable: DevTools
frontend opens against a lab session showing one cell.

**Phase 2 -- multi-target attach.** Attach every cell's `WebContents` as a page
target under the browser-target session; handle cells added/removed at runtime.
`AppSwapResponsiveLabSession` already tracks viewport lifecycle
(`OnViewportAttached` / `OnViewportDetached`) -- reuse that as the hook.

**Phase 3 -- focus mapping.** Cell focus in the Views layer to `setFlavor` on
the frontend. Needs a browser to frontend channel; the lab already has a Mojo
page handler (`app_swap_responsive_lab_page_handler.{h,cc}`).

**Phase 4 -- reconcile the bespoke inspector.** See section 6.

**Phase 5 -- device catalog.** Feed `EmulatedDevices.ts` (2,183 lines of device
definitions, UA strings, UA metadata, DSF, touch, display features) into the
cell presets. Data port only.

---

## 6. Decision needed: what happens to the existing inspector

The bespoke inspector and DevTools reuse are **not the same instrument**:

- `AppSwapResponsiveLabInspector` is *fan-out* -- one action across all
  viewports at once, per-viewport matched rules (the interesting part: the same
  selector matches different rules at different widths), merged console tagged
  by viewport.
- DevTools reuse is *focus one cell* in depth.

These are complementary. Recommendation: **keep both.** Keep the fan-out panel
for cross-viewport work, add DevTools for depth on the focused cell. Do not
delete the inspector in Phase 4 -- its cross-viewport CSS comparison has no
DevTools equivalent.

---

## 7. Do NOT reuse `panels/emulation/`

`DeviceModeModel` is a singleton hard-bound to the primary page target
(`models/emulation/DeviceModeModel.ts:488`):

```js
if (emulationModel.target() === this.#targetManager.primaryPageTarget() && ...)
```

It will fight this design. Responsive Lab already owns sizing and layout. Take
`EmulatedDevices.ts` (data) and leave `DeviceModeView` / `DeviceModeModel`
alone.

Also relevant: `InspectedPagePlaceholder` renders nothing -- it measures its
rect and calls `setInspectedPageBounds`, and the browser positions the real
page into that hole. One rect, one page. Not reusable for N cells.

---

## 8. Load-bearing protocol caveat (already known, keep honoring)

From `app_swap_responsive_lab_viewport_client.h` -- `setDeviceMetricsOverride`
must be sent with `dontSetVisibleSize: true`. Without it `EmulationHandler`
calls `WebContents::SetDeviceEmulationSize`, which resizes the
`RenderWidgetHostView` directly and fights both `PinnedSizeWebView` and
`NativeViewHost::Layout()` for the cell's native surface size.

Also: canvas scale is handed to the *renderer*, not the compositor, so text
stays sharp when zoomed. `AppSwapResponsiveLabCellView::SetScale` documents a
past double-application bug (150% rendered as 225%) -- re-read that comment
before touching scale.

---

## 9. Repo workflow

```bash
./scripts/sync-chromium.sh     # sync src/ to chromium_version.txt (shallow, --no-history)
./scripts/apply-patches.sh     # reset src/ and apply patches/ in order
./scripts/build.sh             # gn gen out/Release + build (~8h on a slow Mac)
./scripts/update-patches.sh    # regenerate patches/ from uncommitted src/ changes
```

- `apply-patches.sh` does `git reset --hard` on `src/` first. Do not leave
  unrelated work in `src/` uncommitted.
- It now **checks `src/` HEAD against `chromium_version.txt` before resetting**
  and refuses on mismatch. Override with `APPSWAP_SKIP_VERSION_CHECK=1` -- which
  is what you want when deliberately rebasing the patch set onto a new revision.
- New work becomes a new patch file; declare its file list in a `gen` call in
  `update-patches.sh`.
- Changes under `src/third_party/devtools-frontend/src` are a **separate git
  repo** and a separate patch; `apply-patches.sh` routes any patch whose name
  matches `*devtools-frontend*` there.
- Frontend changes in section 2 therefore land as a devtools-frontend patch,
  and C++ changes in section 3 as a regular one.

---

## 10. Open questions

1. Host surface for the frontend -- embedded in the lab panel, or separate
   window? (Phase 1; docking is unavailable either way.)
2. Does a browser-target session raise security/permission concerns worth
   restricting, given it can see every page in the browser?
3. Per-cell CDP session cost with many cells -- the existing viewport clients
   already hold sessions, so measure before assuming.
4. Should the DevTools frontend be a stock build or a patched one? Section 2
   suggests stock may suffice for Elements/Console; Sources isolation
   (section 2 table) would need a frontend patch.

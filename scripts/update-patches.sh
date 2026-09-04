#!/usr/bin/env bash
# Regenerates patches/ from the current uncommitted changes in src/.
#
# Each patch is a logical topic; the list of files per topic is declared in
# the `gen` calls below. Run this before committing so the patches always
# reflect your local source tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/src"

# Include untracked files (e.g. newly added tools) in the diff.
git add -N -A 2>/dev/null || true

# gen <patch-file> <pathspec...> -> writes patches/<patch-file> from the diff
# restricted to the given paths.
#
# Diffs against HEAD explicitly, not the index: `apply-patches.sh` uses
# `git apply --3way`, which stages successfully-merged files as a side
# effect, so a plain `git diff` (working tree vs. index) can go blind to
# real changes right after reapplying patches.
gen() {
  local name="$1"
  local out="$ROOT/patches/$name"
  shift
  if git diff --quiet HEAD -- "$@"; then
    rm -f "$out"
    echo "  (no changes) $name"
  else
    git diff --binary HEAD -- "$@" > "$out"
    echo "  wrote $name"
  fi
}

# Same as gen(), but for files inside third_party/devtools-frontend/src,
# which is its own nested git checkout (pulled via DEPS) rather than part of
# src/'s own git index -- a plain `git diff` from src/ never sees changes
# there, so these need their own repo root and their own apply step (see
# apply-patches.sh's matching *devtools-frontend* special case).
DEVTOOLS_DIR="$ROOT/src/third_party/devtools-frontend/src"

gen_devtools() {
  local name="$1"
  local out="$ROOT/patches/$name"
  shift
  if git -C "$DEVTOOLS_DIR" diff --quiet HEAD -- "$@"; then
    rm -f "$out"
    echo "  (no changes) $name"
  else
    git -C "$DEVTOOLS_DIR" diff --binary HEAD -- "$@" > "$out"
    echo "  wrote $name"
  fi
}

# Binary icon assets (PNG/ICO/ICNS) are tracked as plain files under
# resources/, at the same path they occupy in src/, rather than as diffs in
# a *.patch -- a `git diff --binary` of an image is an opaque base64 blob
# that can't be reviewed and re-encodes the *entire* file on every
# regeneration, even for a one-pixel change. sync_binary_resources() below
# just copies src/<path> to resources/<path>; apply-patches.sh copies them
# back afterwards (see its own "Restoring binary resources" step). Text
# assets that sit alongside these (BRANDING, product_logo.svg, the
# Contents.json manifests inside Assets.xcassets) stay in the normal
# patches/ flow below -- they diff and review just like any other text file.
BINARY_RESOURCES=(
  chrome/app/theme/chromium/product_logo_128.png
  chrome/app/theme/chromium/product_logo_16.png
  chrome/app/theme/chromium/product_logo_22_mono.png
  chrome/app/theme/chromium/product_logo_24.png
  chrome/app/theme/chromium/product_logo_256.png
  chrome/app/theme/chromium/product_logo_48.png
  chrome/app/theme/chromium/product_logo_64.png
  chrome/app/theme/chromium/win/chromium.ico
  chrome/app/theme/chromium/win/app_list.ico
  chrome/app/theme/chromium/win/isolated.ico
  chrome/app/theme/chromium/win/incognito.ico
  chrome/app/theme/chromium/win/chromium_doc.ico
  chrome/app/theme/chromium/win/chromium_pdf.ico
  chrome/app/theme/chromium/mac/app.icns
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/appicon_16.png
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/appicon_32.png
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/appicon_64.png
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/appicon_128.png
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/appicon_256.png
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/appicon_512.png
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/appicon_1024.png
  chrome/app/theme/chromium/mac/Assets.xcassets/Icon.iconset/icon_256x256.png
  chrome/app/theme/chromium/mac/Assets.xcassets/Icon.iconset/icon_256x256@2x.png
  chrome/app/theme/default_100_percent/chromium/product_logo_16.png
  chrome/app/theme/default_100_percent/chromium/product_logo_32.png
  chrome/app/theme/default_100_percent/chromium/linux/product_logo_16.png
  chrome/app/theme/default_100_percent/chromium/linux/product_logo_32.png
  chrome/app/theme/default_200_percent/chromium/product_logo_16.png
  chrome/app/theme/default_200_percent/chromium/product_logo_32.png
)

sync_binary_resources() {
  echo "Syncing binary resources..."
  for rel in "${BINARY_RESOURCES[@]}"; do
    local dest="$ROOT/resources/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$rel" "$dest"
  done
}

echo "Generating patches..."

sync_binary_resources

# The exclude() below carves each locale scripts/update-translations.py
# has actually generated AppSwap-specific translations for out of this
# patch's otherwise-blanket xtb glob, so that locale's translations live
# solely in 0018-i18n-*.patch instead of being captured redundantly here
# too -- see that patch's own comment. Every other (not-yet-touched)
# locale's xtb stays owned by this glob as before (still just the
# original vanilla-Chromium "Chromium"->"AppSwap" substitution from this
# patch's own initial rebrand). When a future session adds another
# locale's translations to 0018, add that locale's exclude() here in the
# SAME change -- excluding a locale here without 0018 covering it yet
# would silently drop its existing translations from every patch.
gen 0001-branding.patch \
  chrome/app/chromium_strings.grd \
  chrome/app/password_manager_ui_strings.grdp \
  chrome/app/settings_chromium_strings.grdp \
  components/components_chromium_strings.grd \
  'components/strings/components_chromium_strings_*.xtb' \
  ':(exclude)components/strings/components_chromium_strings_ru.xtb' \
  ':(exclude)components/strings/components_chromium_strings_es.xtb' \
  extensions/strings/extensions_chromium_strings.grdp \
  'extensions/strings/extensions_strings_*.xtb' \
  chrome/app/theme/chromium/BRANDING \
  chrome/app/theme/chromium/mac/Assets.xcassets/AppIcon.appiconset/Contents.json \
  chrome/app/theme/chromium/mac/Assets.xcassets/Contents.json \
  chrome/app/theme/chromium/product_logo.svg

gen 0002-binary-rename.patch \
  build/win/reorder-imports.py \
  chrome/BUILD.gn \
  chrome/app/chrome_dll.ver \
  chrome/app/chrome_exe.ver \
  chrome/app/chrome_renderer_dll.ver \
  chrome/app/version_assembly/version_assembly_manifest.template \
  chrome/chrome_elf/BUILD.gn \
  chrome/chrome_elf/chrome_elf.def \
  chrome/chrome_elf/chrome_elf_constants.cc \
  chrome/chrome_proxy/BUILD.gn \
  chrome/chrome_proxy/chrome_proxy.ver \
  chrome/chrome_proxy/chrome_proxy_main_win.cc \
  chrome/common/chrome_constants.cc \
  chrome/common/chrome_constants.h \
  chrome/installer/util/util_constants.h \
  chrome/notification_helper/BUILD.gn \
  chrome/notification_helper/notification_helper_exe.ver \
  chrome/browser/web_applications/chrome_pwa_launcher/BUILD.gn \
  chrome/browser/web_applications/chrome_pwa_launcher/chrome_pwa_launcher.ver \
  chrome/browser/web_applications/chrome_pwa_launcher/chrome_pwa_launcher_util.cc \
  components/crash/win/BUILD.gn \
  components/crash/win/chrome_wer.def \
  components/crash/win/chrome_wer.ver \
  chrome/tools/build/win/FILES.cfg \
  chrome/installer/mini_installer/BUILD.gn \
  chrome/installer/mini_installer/chrome.release

gen 0003-install-branding.patch \
  chrome/install_static/chromium_install_modes.h \
  chrome/installer/launcher_support/chrome_launcher_support.cc \
  chrome/installer/mini_installer/mini_installer_constants.cc \
  chrome/installer/setup/setup_util.cc \
  chrome/installer/setup/uninstall.cc \
  chrome/installer/util/logging_installer.cc \
  chrome/common/chrome_content_client.cc

gen 0004-portable-scheme-pak.patch \
  chrome/tools/build/win/create_portable_archive.py \
  chrome/chrome_paks.gni \
  chrome/test/BUILD.gn \
  ui/base/resource/resource_bundle.cc \
  ui/base/resource/resource_bundle_mac.mm \
  content/common/url_schemes.cc \
  content/public/common/url_constants.h \
  content/public/common/url_utils.cc \
  chrome/browser/browser_about_handler.cc \
  chrome/browser/browser_about_handler.h \
  chrome/browser/profiles/profile_io_data.cc

gen 0005-app-routing.patch \
  chrome/browser/app_swap/app_swap_apps_service.cc \
  chrome/browser/app_swap/app_swap_apps_service.h \
  chrome/browser/app_swap/app_swap_artifact_provider.cc \
  chrome/browser/app_swap/app_swap_artifact_provider.h \
  chrome/browser/app_swap/app_swap_apps_ui.cc \
  chrome/browser/app_swap/app_swap_apps_ui.h \
  chrome/browser/app_swap/app_swap_routes_service.cc \
  chrome/browser/app_swap/app_swap_routes_service.h \
  chrome/browser/app_swap/app_swap_routes_ui.cc \
  chrome/browser/app_swap/app_swap_routes_ui.h \
  chrome/browser/app_swap/app_swap_route_matcher.cc \
  chrome/browser/app_swap/app_swap_route_matcher.h \
  chrome/browser/app_swap/app_swap_source.h \
  chrome/browser/app_swap/app_swap_url_loader_factory.cc \
  chrome/browser/app_swap/app_swap_url_loader_factory.h \
  chrome/browser/app_swap/BUILD.gn \
  chrome/browser/BUILD.gn \
  chrome/browser/chrome_content_browser_client.cc \
  chrome/browser/ui/webui/BUILD.gn \
  chrome/browser/ui/webui/chrome_web_ui_configs.cc

gen 0006-disable-ai-mode.patch \
  components/omnibox/common/omnibox_feature_configs.cc \
  testing/variations/fieldtrial_testing_config.json

gen 0007-appswap-scheme-omnibox-badge.patch \
  chrome/browser/ui/toolbar/BUILD.gn \
  chrome/browser/ui/toolbar/chrome_location_bar_model_delegate.cc \
  chrome/browser/ui/views/location_bar/BUILD.gn \
  chrome/browser/ui/views/location_bar/location_icon_state_helper.cc \
  chrome/browser/ui/views/page_info/BUILD.gn \
  chrome/browser/ui/views/page_info/page_info_bubble_view.cc \
  chrome/browser/ui/views/page_info/page_info_main_view.cc \
  components/page_info/page_info.cc \
  components/omnibox/browser/BUILD.gn \
  components/omnibox/browser/vector_icons/npm_package.icon

gen 0008-app-profiles.patch \
  chrome/browser/app_swap/app_swap_profiles_service.cc \
  chrome/browser/app_swap/app_swap_profiles_service.h \
  chrome/browser/app_swap/app_swap_profiles_ui.cc \
  chrome/browser/app_swap/app_swap_profiles_ui.h

gen 0009-tab-strip-profile-button.patch \
  chrome/browser/ui/views/app_swap/BUILD.gn \
  chrome/browser/ui/views/app_swap/app_swap_profile_switch_util.cc \
  chrome/browser/ui/views/app_swap/app_swap_profile_switch_util.h \
  chrome/browser/ui/views/app_swap/app_swap_profile_tab_strip_button.cc \
  chrome/browser/ui/views/app_swap/app_swap_profile_tab_strip_button.h \
  chrome/browser/ui/BUILD.gn \
  chrome/browser/ui/views/frame/horizontal_tab_strip_region_view.cc \
  chrome/browser/ui/views/frame/horizontal_tab_strip_region_view.h \
  chrome/browser/ui/views/location_bar/location_bar_view.cc \
  chrome/browser/ui/views/location_bar/location_bar_view.h

gen_devtools 0010-devtools-disable-paste-guard.patch \
  front_end/panels/console/ConsoleView.ts \
  front_end/panels/console/ConsolePinPane.ts \
  front_end/panels/console/ConsolePrompt.ts

# Changes to app_swap_artifact_provider.{cc,h}, page_info_bubble_view.cc, and
# the views/app_swap and page_info BUILD.gn files that this feature also
# touches are already covered by 0005/0007/0009 above -- re-running gen()
# for those picks up these additions automatically. Only genuinely new files
# belong here.
gen 0011-npm-version-picker.patch \
  chrome/browser/app_swap/app_swap_version_utils.cc \
  chrome/browser/app_swap/app_swap_version_utils.h \
  chrome/browser/ui/views/app_swap/app_swap_version_picker_dialog.cc \
  chrome/browser/ui/views/app_swap/app_swap_version_picker_dialog.h \
  chrome/browser/ui/views/controls/rich_hover_button.cc

# Per-tab persistence: AppSwap Profile pins and npm version pins each survive
# a session restore via a small per-tab helper that reads/writes
# SessionService extra data. Changes to already-covered files this feature
# also touches (app_swap_profile_switch_util.cc, app_swap_url_loader_factory.*,
# page_info_bubble_view.cc, the app_swap/BUILD.gn and ui/BUILD.gn files) are
# picked up automatically by 0005/0007/0009/0011 above.
gen 0012-tab-level-persistence.patch \
  chrome/browser/app_swap/app_swap_profile_pin_tab_helper.cc \
  chrome/browser/app_swap/app_swap_profile_pin_tab_helper.h \
  chrome/browser/app_swap/app_swap_profile_removal_util.cc \
  chrome/browser/app_swap/app_swap_profile_removal_util.h \
  chrome/browser/app_swap/app_swap_profile_session_restore_util.cc \
  chrome/browser/app_swap/app_swap_profile_session_restore_util.h \
  chrome/browser/app_swap/app_swap_version_pin_tab_helper.cc \
  chrome/browser/app_swap/app_swap_version_pin_tab_helper.h \
  chrome/browser/ui/browser_tabrestore.cc \
  chrome/browser/ui/tab_helpers.cc

# Periodic npm dist-tag update checker. The "update available" affordance
# lives in the toolbar Reload button itself (green "Update" highlight +
# tooltip with the target version, click performs the update-reload) rather
# than a separate address-bar badge -- app_swap_update_badge_view.* was
# deleted in favor of app_swap_reload_button_controller.* below.
# testing/variations/fieldtrial_testing_config.json also disables the
# WebUIReloadButtonStudy field trial there, since that study silently swaps
# in an experimental WebUI-based reload button that bypasses ReloadButton
# entirely; that file is already covered by 0006 above. Changes to other
# already-covered files this feature also touches
# (app_swap_version_pin_tab_helper.*, app_swap_artifact_provider.*,
# app_swap_url_loader_factory.*, page_info_bubble_view.cc,
# app_swap_version_picker_dialog.cc, location_bar_view.*,
# location_icon_state_helper.cc, tab_helpers.cc, and the various BUILD.gn
# files) are picked up automatically by 0005/0007/0009/0011/0012 above.
gen 0013-npm-update-checker.patch \
  chrome/browser/app_swap/app_swap_prefs.cc \
  chrome/browser/app_swap/app_swap_prefs.h \
  chrome/browser/app_swap/app_swap_update_available_tab_helper.cc \
  chrome/browser/app_swap/app_swap_update_available_tab_helper.h \
  chrome/browser/app_swap/app_swap_update_checker.cc \
  chrome/browser/app_swap/app_swap_update_checker.h \
  chrome/browser/ui/views/app_swap/app_swap_reload_button_controller.cc \
  chrome/browser/ui/views/app_swap/app_swap_reload_button_controller.h \
  chrome/browser/ui/views/toolbar/reload_button.cc \
  chrome/browser/ui/views/toolbar/reload_button.h \
  chrome/browser/ui/views/toolbar/toolbar_view.cc \
  chrome/browser/ui/views/toolbar/toolbar_view.h \
  chrome/browser/ui/views/toolbar/BUILD.gn \
  chrome/browser/prefs/browser_prefs.cc \
  chrome/browser/prefs/BUILD.gn

# The "Switch version" UI, rebuilt as a WebUI (Mojo + Lit) page hosted as a
# Page Info sub-page (like "Cookies and Site Data") rather than the native
# ui::DialogModel-based popup app_swap_version_picker_dialog.cc used to show
# -- that file now just builds a views::WebView pointed at
# chrome://appswap-version-picker/ instead, still covered by 0011 above.
# page_info_bubble_view.h and page_info_navigation_handler.h weren't
# previously touched by any patch (only page_info_bubble_view.cc was, via
# 0007), so they're new here alongside the rest of the plumbing this needed:
# the interface-broker registration switch in
# chrome_browser_interface_binders_webui_parts_desktop.cc, the new GRIT
# resource id range, and the Lit build's third_party visibility entry.
gen 0014-npm-version-picker-webui.patch \
  chrome/browser/ui/webui/app_swap_version_picker \
  chrome/browser/resources/app_swap_version_picker \
  chrome/browser/ui/views/page_info/page_info_bubble_view.h \
  chrome/browser/ui/views/page_info/page_info_navigation_handler.h \
  chrome/browser/chrome_browser_interface_binders_webui_parts_desktop.cc \
  tools/gritsettings/resource_ids.spec \
  third_party/lit/v3_0/BUILD.gn

# Offline fallback (serve the tab's currently-committed version from disk
# cache when the registry is unreachable, plus a static recovery page
# listing cached versions to pick from) and "Copy link to this version" in
# Page Info added no new files -- every file they touch
# (app_swap_artifact_provider.*, app_swap_url_loader_factory.*,
# page_info_bubble_view.cc) is already covered by 0005/0007 above, so there's
# no patch entry of their own here.

# "Projects": a Project is a real Chromium Profile (not a new lightweight
# entity) -- Apps/Route Groups/the AppSwap Profile (storage-partition)
# sub-identity all become per-Profile KeyedServices (see the *_service.h
# comments) instead of global base::NoDestructor singletons with one shared
# JSON file, registered in chrome_browser_main_extra_parts_profiles.cc as
# Chromium's KeyedService dependency graph requires. AppSwapRoute (origin ->
# app_id) is folded into AppSwapApp.hosts; the old flat, app-independent
# AppSwapRewriteRule becomes AppSwapRouteGroupRule, nested inside a named,
# reusable AppSwapRouteGroup a tab can pin to (see
# app_swap_route_group_pin_tab_helper.h) -- replacing appswap://rewrites and
# the four old chrome.send()-based admin pages (apps/routes/rewrites/
# profiles) with one Mojo+Lit SPA at appswap://projects (General/Apps/
# Routes/Profiles tabs), always scoped to whichever profile's window it's
# opened in. AppSwapRouteGroupTabStripButton (in the location bar, next to
# the existing AppSwap Profile button) shows/switches the active tab's
# pinned Route Group live, mirroring that button's own shape but reading
# real per-tab state rather than a single global active pointer. Changes to
# already-covered files this also touches (app_swap_apps_service.*,
# app_swap_profiles_service.*, app_swap_route_matcher.*,
# app_swap_url_loader_factory.*, app_swap/BUILD.gn, chrome_web_ui_configs.cc,
# browser_about_handler.cc, chrome_browser_interface_binders_webui_parts_desktop.cc,
# ui/webui/BUILD.gn, ui/views/app_swap/BUILD.gn, ui/views/app_swap/BUILD.gn,
# location_bar_view.*, page_info_main_view.cc, page_info_bubble_view.cc,
# location_icon_state_helper.cc, chrome_location_bar_model_delegate.cc,
# tab_helpers.cc, browser_tabrestore.cc, chrome_content_browser_client.cc,
# tools/gritsettings/resource_ids.spec, chrome_paks.gni) are picked up
# automatically by 0004/0005/0007/0009/0013/0014 above. Everything below is
# new: the *_service_factory.* files, the new route-group service/pin-helper,
# the profiles KeyedService registration, the whole appswap://projects
# WebUI, and the new tab-strip button.
#
# Follow-up from a review of the whole patch series. AppSwapConfigStore is
# new here: the three config services had each hand-rolled the same load/save
# machinery, and each copy posted its writes with an unordered
# base::ThreadPool::PostTask (so two quick saves could persist the older
# snapshot) via a non-atomic base::WriteFile (so an interrupted write
# truncated the config), and guarded mutations only with DCHECK(loaded_) --
# in release, an add racing the initial read appended to an empty list and
# then wrote *that* over the real file. The store fixes all three at once and
# the services now just parse/serialize. The unittests are new too: the
# config store's ordering/clobber guarantees, the pure URL matching and
# rewriting logic, and the version/package path validation described in
# app_swap_version_utils.h -- which closes a real hole, since a version
# string reaches the artifact cache path straight from the
# appswap-use-version query parameter (see
# AppSwapProxyingURLLoaderFactory::CreateLoaderAndStart), and an unchecked
# one repointed the serve root anywhere on disk. Also from that review, in
# files already covered above: the admin page gained the edit/rename/delete
# operations its mojom never exposed (leaving four Update* service methods
# dead and the General tab read-only), rewritten route-group requests now go
# through the tab's own StoragePartition factory rather than
# SystemNetworkContextManager's cookie-less one, the artifact cache prunes
# old versions instead of growing forever, served file paths are
# percent-decoded, the matchers return values rather than pointers into a
# vector any config mutation reallocates, and SwitchTabsOffAppSwapProfile
# scopes itself to the calling project's own windows.
gen 0015-projects.patch \
  chrome/browser/app_swap/app_swap_apps_service_factory.cc \
  chrome/browser/app_swap/app_swap_apps_service_factory.h \
  chrome/browser/app_swap/app_swap_config_store.cc \
  chrome/browser/app_swap/app_swap_config_store.h \
  chrome/browser/app_swap/app_swap_config_store_unittest.cc \
  chrome/browser/app_swap/app_swap_route_matcher_unittest.cc \
  chrome/browser/app_swap/app_swap_version_utils_unittest.cc \
  chrome/browser/app_swap/app_swap_profiles_service_factory.cc \
  chrome/browser/app_swap/app_swap_profiles_service_factory.h \
  chrome/browser/app_swap/app_swap_route_group_pin_tab_helper.cc \
  chrome/browser/app_swap/app_swap_route_group_pin_tab_helper.h \
  chrome/browser/app_swap/app_swap_route_group_service.cc \
  chrome/browser/app_swap/app_swap_route_group_service.h \
  chrome/browser/app_swap/app_swap_route_group_service_factory.cc \
  chrome/browser/app_swap/app_swap_route_group_service_factory.h \
  chrome/browser/profiles/BUILD.gn \
  chrome/browser/profiles/chrome_browser_main_extra_parts_profiles.cc \
  chrome/browser/resources/app_swap_projects \
  chrome/browser/ui/views/app_swap/app_swap_route_group_tab_strip_button.cc \
  chrome/browser/ui/views/app_swap/app_swap_route_group_tab_strip_button.h \
  chrome/browser/ui/webui/app_swap_projects

# Project Selector: a leading tab-strip button (before Tab Search, in the
# combo-button's usual position) showing the current Project (== Profile)
# and letting you switch to any other one, or create a new one via the
# stock ProfilePicker -- deliberately a standalone views::MenuButton +
# ui::SimpleMenuModel (same shape as AppSwapProfileTabStripButton/
# AppSwapRouteGroupTabStripButton) rather than a WebUI bubble, so it never
# touches TabSearchButton/TabStripComboButton. Also fixes two real,
# pre-existing null/dangling-pointer crashes this surfaced the first time
# anything actually exercised ProfilePicker::Show() (System Profile
# navigation, and a Profile outliving an AppSwapProxyingURLLoaderFactory
# bound to it) -- both already covered by 0005 above (chrome_content_
# browser_client.cc, app_swap_url_loader_factory.*), along with the new
# button's own frame wiring in horizontal_tab_strip_region_view.* and
# views/app_swap/BUILD.gn (covered by 0009).
#
# Also renames Chromium's own "manageProfile" settings subpage to
# "manageProject" (route.ts + the kManageProfileSubPage constant native
# code uses to open it -- every other reference is to the shared Route
# object or an internal view id, not the path string itself, so only these
# two needed to change) and retextures the stock profile-creation/
# management dialogs' English strings from "profile" to "project" wording
# (profiles_strings.grdp, settings_strings.grdp -- settings_chromium_strings.grdp
# is already covered by 0001 above). The matching Russian retranslations for
# these (and every other AppSwap-specific string) live in
# 0018-i18n-ru-translations.patch instead of here -- see that patch's own
# comment and scripts/update-translations.py for why translations are kept
# in one dedicated patch stream rather than scattered across whichever
# feature patch happened to introduce each string. New message ids for the
# retextured strings were computed with grit's own `xmb` tool against a
# minimal probe .grd (verified by first reproducing the *existing* ids from
# the current Russian translations before trusting the new ones), not
# hand-derived, since grit's fingerprint depends on the exact processed
# message content.
#
# Follow-up in this same patch: the button was rebuilt to reuse Chromium's
# own native profile-switcher bubble (ProfileMenuCoordinator/ProfileMenuView)
# instead of a custom dropdown -- see the button's own class comment for how
# (claiming the kToolbarAvatarButtonElementId anchor identifier, and why its
# two files had to move into //chrome/browser/ui's own sources in
# chrome/browser/ui/BUILD.gn, already covered by 0009, to reach
# ProfileMenuCoordinator without a circular target dependency). More
# "profile" -> "project" retexturing followed in that same bubble
# (chromium_strings.grd -- already covered by 0001 -- and more of
# profiles_strings.grdp), and two rows (Google services settings, Guest)
# were removed from it entirely in profile_menu_view.cc.
#
# Also fixes a whole class of null-deref crashes surfaced by finally
# exercising non-regular profiles for real: AppSwap*ServiceFactory::
# GetForProfile() legitimately returns null for Incognito/Guest/System
# (ProfileKeyedServiceFactory's default ProfileSelections), which several
# call sites dereferenced unchecked -- confirmed via real crash dumps for
# each. Fixed at the shared root where possible (app_swap_route_matcher.cc's
# FindAppSwapAppForUrl/FindAppSwapRouteGroupById, which the location bar,
# Page Info, and the URL loader factory all funnel through) rather than at
# every caller.
gen 0016-project-selector-and-terminology.patch \
  chrome/app/generated_resources.grd \
  chrome/app/profiles_strings.grdp \
  chrome/app/settings_strings.grdp \
  chrome/browser/resources/settings/route.ts \
  chrome/browser/resources/settings/page_visibility.ts \
  chrome/browser/resources/settings/settings_menu/settings_menu.html \
  chrome/browser/resources/settings/settings_menu/settings_menu.ts \
  chrome/browser/resources/settings/settings_main/settings_main.html \
  chrome/browser/resources/settings/people_page/people_page_index.ts \
  chrome/browser/resources/settings/people_page/people_page_index.html.ts \
  chrome/browser/resources/settings/people_page/manage_profile.ts \
  chrome/browser/resources/settings/people_page/manage_profile.html.ts \
  chrome/browser/ui/views/app_swap/app_swap_project_selector_button.cc \
  chrome/browser/ui/views/app_swap/app_swap_project_selector_button.h \
  chrome/browser/ui/views/profiles/profile_menu_view.cc \
  chrome/browser/ui/webui/settings/settings_localized_strings_provider.cc \
  chrome/browser/ui/webui/settings/settings_ui.h \
  chrome/common/webui_url_constants.h

# Responsive Lab: a toolbar toggle (in the main toolbar row, next to Home --
# see toolbar_view.cc -- rather than the location bar, so it reads as a
# browser-chrome mode switch rather than a per-page action) that replaces a
# tab's own content view with a grid of several real viewports of that same
# page, one per device preset (see AppSwapResponsiveLabTabHelper, which owns
# the grid's WebContents and keeps them navigation-synced with the real tab;
# the tab's own WebContents is never touched, which is what keeps the
# address bar working normally throughout). AppSwapResponsiveLabOverlayView
# renders the grid; it's hosted as one more sibling next to ContentsWebView
# inside ContentsContainerView, the same way several other Chromium features
# already overlay that view (ActorOverlayWebView, indigo_overlay_view_,
# etc.) -- see contents_container_view.{cc,h} for the new bounds case,
# following that exact existing pattern rather than a new mechanism.
# AppSwapResponsiveLabButton extends ToolbarButton (like its toolbar-row
# neighbors HomeButton/SplitTabsToolbarButton) rather than a plain
# ImageButton, for the same hover/ink-drop/theme handling those get for
# free; it needs BrowserView::GetContentsContainerViewFor() to reach the
# right container for the active tab, which is why it's listed directly in
# chrome/browser/ui/BUILD.gn's own sources rather than in views/app_swap's
# separate target -- same reasoning as AppSwapProjectSelectorButton, see
# that file's own comment. Changes to already-covered files this also
# touches (chrome/browser/app_swap/BUILD.gn,
# chrome/browser/ui/views/app_swap/BUILD.gn, chrome/browser/ui/BUILD.gn,
# chrome/browser/ui/views/toolbar/toolbar_view.{cc,h},
# chrome/browser/ui/tab_helpers.cc) are picked up automatically by
# 0005/0009/0012/0013 above.
gen 0017-responsive-lab.patch \
  chrome/browser/app_swap/app_swap_responsive_lab_tab_helper.cc \
  chrome/browser/app_swap/app_swap_responsive_lab_tab_helper.h \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_canvas_view.cc \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_canvas_view.h \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_grid_holder.cc \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_grid_holder.h \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_minimap_view.cc \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_minimap_view.h \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_overlay_view.cc \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_overlay_view.h \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_wheel_interceptor_aura.cc \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_wheel_interceptor_aura.h \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_wheel_observer_mac.cc \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_wheel_observer_mac.h \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_button.cc \
  chrome/browser/ui/views/app_swap/app_swap_responsive_lab_button.h \
  chrome/browser/ui/views/frame/contents_container_view.cc \
  chrome/browser/ui/views/frame/contents_container_view.h \
  ui/views/controls/native/native_view_host.cc \
  ui/views/controls/native/native_view_host_mac.mm

# Translations for AppSwap-specific strings (new, or whose English text was
# changed by one of our own patches -- vanilla Chromium's own strings
# already get real translations from Google's own pipeline on every DEPS
# roll, and re-translating those ourselves would just fight upstream).
# Deliberately its own patch, decoupled from the feature patches that
# actually introduced these strings: adding coverage for another locale
# later means regenerating this one patch, not every feature patch that's
# ever touched a translatable string. See scripts/update-translations.py.
# Includes chromium_strings_ru.xtb/generated_resources_ru.xtb's Russian
# retexturing that used to live in 0016's own patch -- moved here for the
# same reason (0016 stayed responsible for the .grd/.grdp English source,
# not the translations). Spanish (es) added the same way once its
# translations were complete -- each new locale just adds its 3 xtb paths
# here, no other patch needs to change (beyond a components/ glob exclude,
# see 0001's own comment above, for locales that glob would otherwise
# capture with untranslated content).
gen 0018-i18n-translations.patch \
  chrome/app/resources/chromium_strings_ru.xtb \
  chrome/app/resources/generated_resources_ru.xtb \
  components/strings/components_chromium_strings_ru.xtb \
  chrome/app/resources/chromium_strings_es.xtb \
  chrome/app/resources/generated_resources_es.xtb \
  components/strings/components_chromium_strings_es.xtb

# Restricts the manual "Display AppSwap in this language" choice in
# chrome://settings/languages to the locales we actually maintain
# AppSwap-specific translations for (TRACKED_LOCALES in
# scripts/update-translations.py) -- gated in l10n_util::IsUserFacingUILocale,
# the single non-ChromeOS chokepoint that feeds
# LanguageSettingsPrivateGetLanguageListFunction's supports_ui flag. All other
# Chromium locales still ship and still work as an OS-detected default UI
# language; they're just not offered as a manual pick, since our own new
# strings would show up as untranslated English there.
gen 0019-supported-ui-locales.patch \
  ui/base/l10n/l10n_util.cc

# Whether `f` (a path relative to src/) is one of the images tracked under
# resources/ instead of as a patch -- sync_binary_resources() above already
# copied it there, so it's covered even though it won't appear in any
# *.patch text.
is_binary_resource() {
  local f="$1"
  for rel in "${BINARY_RESOURCES[@]}"; do
    if [[ "$rel" == "$f" ]]; then
      return 0
    fi
  done
  return 1
}

# Warn about any changed file not covered by one of the patches above (or by
# resources/, for binary assets).
echo "Checking for uncovered changes..."
for f in $(git status --porcelain --untracked-files=no | cut -c4-); do
  case "$f" in
    third_party/win_build_output/*) continue ;;  # generated MIDL output
  esac
  if is_binary_resource "$f"; then
    continue
  fi
  if ! grep -qF "$f" "$ROOT"/patches/*.patch; then
    echo "warning: '$f' is changed but not present in any patch" >&2
  fi
done

# Same check, for the nested devtools-frontend checkout.
for f in $(git -C "$DEVTOOLS_DIR" status --porcelain --untracked-files=no | cut -c4-); do
  if ! grep -qF "$f" "$ROOT"/patches/*.patch; then
    echo "warning: devtools-frontend '$f' is changed but not present in any patch" >&2
  fi
done

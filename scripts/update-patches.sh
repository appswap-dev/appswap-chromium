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

echo "Generating patches..."

gen 0001-branding.patch \
  chrome/app/chromium_strings.grd \
  chrome/app/password_manager_ui_strings.grdp \
  chrome/app/settings_chromium_strings.grdp \
  components/components_chromium_strings.grd \
  'components/strings/components_chromium_strings_*.xtb' \
  extensions/strings/extensions_chromium_strings.grdp \
  'extensions/strings/extensions_strings_*.xtb' \
  chrome/app/theme/chromium/BRANDING \
  chrome/app/theme/chromium/product_logo_128.png \
  chrome/app/theme/chromium/product_logo_16.png \
  chrome/app/theme/chromium/product_logo_22_mono.png \
  chrome/app/theme/chromium/product_logo_24.png \
  chrome/app/theme/chromium/product_logo_256.png \
  chrome/app/theme/chromium/product_logo_48.png \
  chrome/app/theme/chromium/product_logo_64.png \
  chrome/app/theme/chromium/win/chromium.ico \
  chrome/app/theme/default_100_percent/chromium/product_logo_16.png \
  chrome/app/theme/default_100_percent/chromium/product_logo_32.png \
  chrome/app/theme/default_100_percent/chromium/linux/product_logo_16.png \
  chrome/app/theme/default_100_percent/chromium/linux/product_logo_32.png \
  chrome/app/theme/default_200_percent/chromium/product_logo_16.png \
  chrome/app/theme/default_200_percent/chromium/product_logo_32.png

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

# Periodic npm dist-tag update checker + address-bar "update available"
# badge. Changes to already-covered files this feature also touches
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
  chrome/browser/ui/views/app_swap/app_swap_update_badge_view.cc \
  chrome/browser/ui/views/app_swap/app_swap_update_badge_view.h \
  chrome/browser/prefs/browser_prefs.cc \
  chrome/browser/prefs/BUILD.gn

# Warn about any changed file not covered by one of the patches above.
echo "Checking for uncovered changes..."
for f in $(git status --porcelain --untracked-files=no | cut -c4-); do
  case "$f" in
    third_party/win_build_output/*) continue ;;  # generated MIDL output
  esac
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

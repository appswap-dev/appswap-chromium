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
gen() {
  local name="$1"
  local out="$ROOT/patches/$name"
  shift
  if git diff --quiet -- "$@"; then
    rm -f "$out"
    echo "  (no changes) $name"
  else
    git diff --binary -- "$@" > "$out"
    echo "  wrote $name"
  fi
}

echo "Generating patches..."

gen 0001-branding.patch \
  chrome/app/chromium_strings.grd \
  chrome/app/password_manager_ui_strings.grdp \
  chrome/app/settings_chromium_strings.grdp \
  chrome/app/theme/chromium/BRANDING \
  chrome/app/theme/chromium/product_logo_128.png \
  chrome/app/theme/chromium/product_logo_16.png \
  chrome/app/theme/chromium/product_logo_22_mono.png \
  chrome/app/theme/chromium/product_logo_24.png \
  chrome/app/theme/chromium/product_logo_256.png \
  chrome/app/theme/chromium/product_logo_48.png \
  chrome/app/theme/chromium/product_logo_64.png \
  chrome/app/theme/chromium/win/chromium.ico

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
  chrome/browser/app_swap/app_swap_artifact_provider.cc \
  chrome/browser/app_swap/app_swap_artifact_provider.h \
  chrome/browser/app_swap/app_swap_source.h \
  chrome/browser/app_swap/app_swap_tab_state.cc \
  chrome/browser/app_swap/app_swap_tab_state.h \
  chrome/browser/app_swap/app_swap_url_loader_factory.cc \
  chrome/browser/app_swap/app_swap_url_loader_factory.h \
  chrome/browser/app_swap/BUILD.gn \
  chrome/browser/BUILD.gn \
  chrome/browser/chrome_content_browser_client.cc

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

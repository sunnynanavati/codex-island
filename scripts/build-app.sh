#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/packaging/version.env"
variant="${1:-release}"
case "$variant" in
  release) app_name='Codex Island'; bundle_id='com.codexisland.app' ;;
  dev) app_name='Codex Island Dev'; bundle_id='com.codexisland.dev' ;;
  *) echo 'Usage: build-app.sh [release|dev]' >&2; exit 2 ;;
esac
output_dir="${OUTPUT_DIR:-$project_dir/dist}"
mkdir -p "$output_dir"
app_path="$output_dir/$app_name.app"
stage_dir="$(mktemp -d "$output_dir/.bundle.XXXXXX")"
trap 'if [[ -d "$stage_dir" ]]; then /bin/rm -r "$stage_dir"; fi' EXIT
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/codex-island-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/codex-island-module-cache}"
cd "$project_dir"
xcrun swift build --disable-sandbox -c release --arch arm64
bin_dir="$(xcrun swift build --disable-sandbox -c release --arch arm64 --show-bin-path)"
contents="$stage_dir/$app_name.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$bin_dir/CodexIsland" "$contents/MacOS/CodexIsland"
cp "$project_dir/packaging/Info.plist" "$contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$contents/Info.plist"
plutil -replace CFBundleName -string "$app_name" "$contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$app_name" "$contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$contents/Info.plist"
plutil -replace CFBundleVersion -string "$APP_BUILD" "$contents/Info.plist"
for resource in "$bin_dir"/*.bundle; do
  [[ -d "$resource" ]] && ditto "$resource" "$contents/Resources/$(basename "$resource")"
done
cp "$project_dir"/Sources/CodexIsland/Resources/* "$contents/Resources/"
cp "$project_dir/LICENSE" "$contents/Resources/LICENSE.txt"
xcrun swift "$project_dir/scripts/make-icon.swift" "$stage_dir/AppIcon.iconset"
iconutil -c icns "$stage_dir/AppIcon.iconset" -o "$contents/Resources/AppIcon.icns"
identity="${SIGNING_IDENTITY:--}"
if [[ "$identity" == '-' ]]; then
  codesign --force --sign - "$stage_dir/$app_name.app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$stage_dir/$app_name.app"
fi
codesign --verify --strict "$stage_dir/$app_name.app"
if [[ -e "$app_path" ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$existing_id" == "$bundle_id" && ! -L "$app_path" ]] || { echo "Unrecognized output preserved: $app_path" >&2; exit 1; }
  mv "$app_path" "$stage_dir/previous.app"
fi
mv "$stage_dir/$app_name.app" "$app_path"
echo "Built: $app_path ($APP_VERSION, build $APP_BUILD)"
[[ "$identity" != '-' ]] || echo 'Local ad-hoc signature; this artifact is not notarized.'

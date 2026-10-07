#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/packaging/version.env"
output_dir="${OUTPUT_DIR:-$project_dir/dist}"
"$project_dir/scripts/build-app.sh" release
stage_dir="$(mktemp -d "$output_dir/.dmg.XXXXXX")"
trap 'if [[ -d "$stage_dir" ]]; then /bin/rm -r "$stage_dir"; fi' EXIT
ditto "$output_dir/Codex Island.app" "$stage_dir/Codex Island.app"
ln -s /Applications "$stage_dir/Applications"
label='local-unnotarized'
[[ -z "${SIGNING_IDENTITY:-}" ]] || label='signed'
dmg_path="$output_dir/Codex-Island-$APP_VERSION-arm64-$label.dmg"
[[ ! -e "$dmg_path" ]] || { echo "Output already exists; move it before packaging again: $dmg_path" >&2; exit 1; }
hdiutil create -volname 'Codex Island' -srcfolder "$stage_dir" -format UDZO "$dmg_path"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${SIGNING_IDENTITY:-}" && "$SIGNING_IDENTITY" != '-' ]] || { echo 'Notarization requires a Developer ID identity.' >&2; exit 1; }
  xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg_path"
  xcrun stapler validate "$dmg_path"
fi
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path"
echo "Installer: $dmg_path"

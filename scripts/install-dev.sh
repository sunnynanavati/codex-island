#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
variant="${1:-release}"
[[ "$variant" == release || "$variant" == dev ]] || { echo 'Usage: install-dev.sh [release|dev]' >&2; exit 2; }
if [[ "$variant" == dev ]]; then
  source_name='Codex Island Dev'; installed_name='Codex Island Dev'; bundle_id='com.codexisland.dev'
else
  source_name='Codex Island'; installed_name='Codex Island Local'; bundle_id='com.codexisland.app'
fi
if [[ -n "${INSTALL_APP_SOURCE:-}" ]]; then
  install_source="$INSTALL_APP_SOURCE"
else
  "$project_dir/scripts/build-app.sh" "$variant"
  install_source="${OUTPUT_DIR:-$project_dir/dist}/$source_name.app"
fi
source_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$install_source/Contents/Info.plist" 2>/dev/null || true)"
[[ "$source_id" == "$bundle_id" && -x "$install_source/Contents/MacOS/CodexIsland" ]] || { echo "Invalid install source: $install_source" >&2; exit 1; }
codesign --verify --strict "$install_source"
destination="$HOME/Applications/$installed_name.app"
legacy_app="$HOME/Library/Application Support/CodexIsland/Codex Island.app"
legacy_plist="$HOME/Library/LaunchAgents/com.codexisland.app.plist"
stop_exact_executable() {
  local executable="$1" process_id
  [[ -x "$executable" && ! -L "$executable" ]] || return 0
  while read -r process_id; do
    [[ -n "$process_id" ]] || continue
    # Match the kernel-reported executable path, not app name or bundle ID.
    [[ "$(ps -ww -p "$process_id" -o comm=)" == "$executable" ]] || continue
    kill -TERM "$process_id"
    for attempt in 1 2 3 4 5; do
      kill -0 "$process_id" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$process_id" 2>/dev/null; then
      echo "App did not quit; preserved installation at $executable" >&2
      exit 1
    fi
  done < <(ps -ww -axo pid=,comm= | awk -v target="$executable" '{pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0==target) print pid}')
}
if [[ -f "$legacy_plist" ]]; then
  legacy_label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$legacy_plist" 2>/dev/null || true)"
  legacy_program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$legacy_plist" 2>/dev/null || true)"
  if [[ "$legacy_label" == com.codexisland.app && "$legacy_program" == "$legacy_app/Contents/MacOS/CodexIsland" ]]; then
    launchctl bootout "gui/$(id -u)/com.codexisland.app" 2>/dev/null || true
    backup_dir="$(mktemp -d "$HOME/Library/Application Support/CodexIsland/legacy-migration.XXXXXX")"
    mv "$legacy_plist" "$backup_dir/"
    echo "Retired LaunchAgent saved at: $backup_dir"
  else
    echo "Unrecognized LaunchAgent preserved: $legacy_plist" >&2
    exit 1
  fi
fi
standalone_plist="$HOME/Library/LaunchAgents/local.codex-island.plist"
if [[ -f "$standalone_plist" ]]; then
  standalone_label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$standalone_plist" 2>/dev/null || true)"
  standalone_program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$standalone_plist" 2>/dev/null || true)"
  if [[ "$standalone_label" == local.codex-island && "$standalone_program" == "$HOME/Library/Application Support/CodexIsland/CodexIsland" ]]; then
    launchctl bootout "gui/$(id -u)/local.codex-island" 2>/dev/null || true
    backup_dir="$(mktemp -d "$HOME/Library/Application Support/CodexIsland/legacy-migration.XXXXXX")"
    mv "$standalone_plist" "$backup_dir/"
    echo "Retired standalone LaunchAgent saved at: $backup_dir"
  else
    echo "Unrecognized standalone LaunchAgent preserved: $standalone_plist" >&2
    exit 1
  fi
fi
legacy_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$legacy_app/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$legacy_id" == com.codexisland.app ]]; then
  stop_exact_executable "$legacy_app/Contents/MacOS/CodexIsland"
fi
stop_exact_executable "$HOME/Library/Application Support/CodexIsland/CodexIsland"
mkdir -p "$HOME/Applications"
for launcher in "$HOME/Applications/Codex Island.app" "$HOME/Applications/Codex Island Local.app"; do
  if [[ -L "$launcher" && "$(readlink "$launcher")" == "$legacy_app" ]]; then
    unlink "$launcher"
  fi
done
if [[ -e "$destination" ]]; then
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$existing_id" == "$bundle_id" && ! -L "$destination" ]] || { echo "Existing unrelated app preserved: $destination" >&2; exit 1; }
  stop_exact_executable "$destination/Contents/MacOS/CodexIsland"
  backup_dir="$(mktemp -d "$HOME/Applications/.codex-island-backup.XXXXXX")"
  mv "$destination" "$backup_dir/$installed_name.app"
  echo "Previous app preserved: $backup_dir"
fi
ditto "$install_source" "$destination"
open "$destination" --args --show-settings
echo "Installed: $destination"
echo 'Launch at Login is optional in Settings. No Accessibility permission is needed.'
echo 'This local build is ad-hoc signed and unnotarized; public distribution needs Developer ID signing.'

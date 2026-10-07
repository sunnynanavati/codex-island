#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_dir/dist}"
mkdir -p "$output_dir"
export_dir="$(mktemp -d "$output_dir/CodexIsland-source.XXXXXX")"
for item in Package.swift LICENSE README.md CONTRIBUTING.md CHANGELOG.md SECURITY.md PRIVACY.md .gitignore Sources Tests scripts packaging .github; do
  [[ ! -e "$project_dir/$item" ]] || ditto "$project_dir/$item" "$export_dir/$item"
done
"$project_dir/scripts/audit-source.sh" "$export_dir"
echo "Reviewable source export: $export_dir"

# Contributing

Codex Island targets Apple silicon and macOS 14 or newer, using Swift 6, SwiftUI, AppKit, and Swift Package Manager. No third-party code dependencies are required.

Run `swift test` and `swift build -c release` before proposing a change. Use synthetic fixtures for parser, task state, quota, and presentation tests; never commit local Codex data. `swift run CodexIsland --preview-state multiple` shows a synthetic island. Close preview processes when finished.

Keep configuration in the Settings window, preserve keyboard access and Reduce Motion, and keep monitoring read-only. Test motion on an actual notched display where available. Report visual observations separately from performance measurements.

`scripts/build-app.sh dev` builds a separate development bundle. `scripts/install-dev.sh dev` installs it locally. Quit the release app before development work. Use `scripts/package-release.sh` for a local unnotarized disk image. Version and build numbers live in `packaging/version.env`.

Before publication, run `scripts/export-source.sh`, inspect the export, test the disk image on a clean Mac/account, and complete Developer ID signing and notarization. The CI workflow validates changes and stores a temporary build artifact; it does not publish releases.

Describe the user-visible change and verification in contributions. Do not include private task titles, workspace paths, tokens, databases, or rollout files in issues or patches. Contributions are licensed under MIT.

# Codex Island

A native macOS status utility for local Codex chats. A black island joins the MacBook notch, with one cube per active chat and a persistent account-quota ring. Hover for a preview; click to expand activity and quota. All customization lives in a separate Settings window.

## Requirements and installation

Apple silicon, macOS 14 or newer, and a local Codex installation are required. A built-in notched display gives the intended layout; other displays use a centered fallback. End users do not need Xcode or Swift to run an installed app.

Open the disk image, drag **Codex Island** into **Applications**, then open the app. The menu-bar icon provides Settings, Show/Hide Island, Open Codex, and Quit. Closing Settings leaves monitoring running; Quit exits the application. Launch at Login is optional and off for new installations.

Current artifacts are **local, ad-hoc signed, and unnotarized**. They are prepared for testing, not yet a frictionless public download. Gatekeeper may block downloaded copies. A public release must complete Developer ID signing, notarization, and clean-Mac testing; do not disable Gatekeeper globally.

## Features and customization

- Read-only local task monitoring with incremental, partial-line-safe rollout tailing and runtime SQLite schema discovery.
- Stable chat cubes, attention states, recent tasks, pending questions, daily completed turns and approximate active time.
- Nunito status typography and an always-visible quota number; unavailable quota displays a dash, and below 25% remaining is red.
- Compact status words use a spring text reveal with the shared shimmer. Hover “active chats today” counts distinct local chats in Codex’s daily user-interaction timestamps, not currently running tasks. Codex does not expose a reliable history of read-only opens, so those cannot currently be included. Missing daily-interaction data displays a dash rather than zero.
- Compact, hover, and pinned views share interruptible presentation motion and notch clearance.
- Idle shows only a solved green cube and the quota ring. Working chats expand both wings symmetrically; completed peers stay until all chats finish, then the island contracts after the final cube fill.
- Settings pages for General, Appearance, Layout, Motion, Presets, and Advanced & About; live customization and synthetic previews.
- Local presets capture visual preferences without task or account information.
- Reduce Motion, Increased Contrast, keyboard controls, and VoiceOver labels.

Hover to preview, click to pin, and use Escape, outside click, or Collapse to dismiss. After dismissal, move the pointer out before hovering again. The compact/hover island does not take keyboard focus. Task and question actions open Codex; direct answer injection and exact task navigation are not supported by a stable public API.

The rail keeps at least 24 physical pixels between each component group, the physical notch, and the start of the wave. This is 12 points on a 2× Retina display. Wings remain equal in width, so the smaller group has more clearance. Layout’s Working island size applies while working or requiring attention; idle always fits its contents. Settings previews include mixed completion and a replayable final completion.

## Build, test, and package

Developers need Swift 6 and Xcode or matching Command Line Tools:

```sh
swift run
swift test
swift build -c release
./scripts/build-app.sh
./scripts/package-release.sh
```

Outputs are written under `dist/`: an application bundle and a compressed disk image containing the app and an Applications shortcut. Version metadata is in `packaging/version.env`. Packaging targets arm64 and bundles fonts, licenses, SwiftPM resources, and an original generated icon. Existing disk images are preserved; move one aside before rebuilding the same version.

```sh
./scripts/install-dev.sh        # Local release bundle in ~/Applications
./scripts/install-dev.sh dev    # Separate development bundle/preferences
```

To exercise the same migration and install path from a mounted release disk image,
set `INSTALL_APP_SOURCE` to its **Codex Island.app** path before running the installer.
The installer validates the bundle identifier and signature and skips rebuilding.

The installer preserves existing preferences, retires only the verified legacy Codex Island LaunchAgent, backs up replaced app bundles, and opens Settings. It does not register automatic startup. Use Settings to opt in. Legacy launcher links are removed only if they point to the known previous installation. Unrelated applications are preserved.

SwiftPM inside another filesystem sandbox may need `--disable-sandbox`; this affects the build sandbox, not read-only monitoring. Development and release live instances should not overlap.

Synthetic previews:

```sh
swift run CodexIsland --preview-state multiple
swift run CodexIsland --render-previews /tmp/codex-island-previews
swift run CodexIsland --record-motion /tmp/codex-island-motion
```

These use fixture data. Close standalone preview processes when finished. Review actual transitions on a display as well as still images.
Motion recording opens a synthetic native island briefly and exports normal-speed and 3× slower GIFs of only its own surface. Quit the live app first to avoid overlapping islands. This is a visual review tool, not a frame-rate benchmark.

## Public release workflow

`scripts/export-source.sh` produces an allowlisted source export under `dist/` and checks for common secret patterns, personal paths, and private runtime files. Inspect that export before publication. Local plans, logs, databases, build output, and Git history are excluded. No script commits, pushes, creates repositories, or publishes a release.

Optional signing and notarization use credentials already in the macOS Keychain:

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
NOTARY_PROFILE='your-keychain-profile' ./scripts/package-release.sh
```

Developer ID builds enable hardened runtime and timestamp signing. The optional notarization step submits the disk image, waits for acceptance, and staples and validates its ticket. Never commit certificates or credentials. CI tests, packages, and stores a temporary unnotarized artifact; automatic releases and in-app updates are deferred.

Before publication: test a clean user account/Mac, verify login startup and uninstall, review accessibility and live motion, complete signing/notarization, and configure a private security-reporting channel. Intel builds are not included in this milestone.

## Architecture and privacy

SwiftUI renders the island and Settings; a non-activating AppKit panel handles notch placement and Spaces. One presentation coordinator drives frame and contour motion. A shared preferences store keeps settings and island aligned. Monitoring discovers `~/.codex/state_5.sqlite` columns and tails associated JSONL files off the main thread. Transient read failures retain the previous successful task snapshot.

Task states are event-derived heuristics. Completed/cancelled turns and stale data must not remain animated indefinitely. Daily active time is approximate, especially when older history lies outside bounded initial tails. Cubes group child agents under their parent chats.

Quota comes from Codex's persistent local `app-server` backend. Codex performs the authenticated network read; Island does not read credentials or make direct HTTP requests. Reads occur no more than once every five minutes; available notifications update quota without extra calls. Cached values expire after ten minutes or the reported reset, whichever comes first. The core Codex bucket's longest window is shown; old rollout quota is not substituted for unavailable live values. Task refresh is independent of quota work.

No Island account, analytics, or telemetry. Codex files stay read-only. See [Privacy](PRIVACY.md), [Security](SECURITY.md), and [Contributing](CONTRIBUTING.md).

## Troubleshooting and uninstall

- Missing tasks: open Codex and refresh; verify local Codex data exists. Changed schemas/files can temporarily prevent reading.
- Quota unavailable: sign in through Codex and allow the bounded refresh interval. `swift run CodexIsland --diagnose` reports source availability.
- Placement or clipping: adjust Layout and typography in Settings. Very different display setups need calibration.
- Login startup: inspect Settings → General and macOS Login Items. Local unnotarized builds may have platform restrictions; public signing must be verified separately.
- Quit from the menu-bar icon before reinstalling. No development LaunchAgent should restart the app.

To uninstall, turn off Launch at Login, choose Quit, and move the installed application to Trash in Finder. Optional local preferences and presets can be reset from Settings first. Legacy migration backups remain recoverable in their printed locations. Never remove `~/.codex` to uninstall Island.

AppKit cannot guarantee overlay visibility above every system surface or in every Space. Task navigation and question submission remain Codex handoffs. This project is independent of OpenAI.

## License

MIT; see [LICENSE](LICENSE). Bundled Nunito and Inter Tight fonts use the SIL Open Font License; their licenses are included in `Sources/CodexIsland/Resources`. Compact-rail typography remains customizable; expanded tray typography uses Inter Tight, matching the Penpot design.

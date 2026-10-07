# Local installable-app validation

## Delivered

Version 0.2.0 (build 2), Apple silicon, macOS 14+. Dedicated Settings window, menu-bar lifecycle, shared versioned preferences, local presets, isolated synthetic previews, configurable motion, independent task/quota monitoring, optional login registration, app/DMG packaging, and publication documentation.

Apple Design and SwiftUI UI Patterns informed the native sidebar/forms. Animation review guidance informed interruptible geometry, bounded status layers, and stopped hidden previews. Accessibility guidance informed native controls, labels, semantic colors, and motion overrides. Open-source preparation uses an allowlisted export rather than publishing the working directory.

## Verified locally

- 87 tests pass, including migration, presets, shared preferences, slow quota independence, duplicate monitoring, synthetic isolation, maximum typography/layout, and motion stop/restart.
- Release build succeeds; arm64 executable; strict ad-hoc signature verification succeeds.
- Disk image checksum verifies. App installed from the mounted image, then launched from the installed copy. Repeated installer runs preserve previous bundles.
- Both verified legacy startup jobs were retired into recoverable migration backups. Unrelated apps and disabled legacy files remain untouched.
- Native Settings pages inspected through the running app. Appearance preview switches compact/expanded; native controls expose accessibility labels.
- Closing Settings leaves the app alive; opening the bundle again presents Settings. Explicit duplicate executable launch exits without another monitor.
- Command-Q exits without immediate restart. App subsequently relaunched successfully.
- Launch at Login shown off. Registration uses SMAppService; no login preference was silently enabled.
- Expanded island exposes recent tasks, refresh, collapse, and Open Codex, with no settings control. Escape collapses it.
- Startup logs show successful task and live quota reads, with no new crash or repeated-error messages during verification.
- Source export passes the personal-path, credential-pattern, runtime-file, and unrelated-integration scan. No Git publication performed.

## Visual observations versus measurements

A local click/expand/Escape recording was captured. Sampled transition frames retain the rounded contour; no square surface was apparent in those inspected frames. This is not a full normal-speed and slowed-playback certification, nor a frame-rate measurement. Hover, rapid reversal, and all accessibility/display combinations still need the complete manual matrix.

Before migration, two old processes were present. Point samples showed approximately 5.5% CPU / 24 MiB resident for the standalone process and 2% / 95 MiB for the older bundle; these were not controlled workloads.

The new installed app, with Settings closed and a live chat active, consumed 1.32 CPU seconds over a 10-second sample (about 13.2% of one core) and approximately 187 MiB resident. Instantaneous CPU samples ranged from 0.9% to 4.3% during that interval; UI-interaction samples were higher. Task output and monitoring workload were changing, so this is not a valid before/after performance comparison. Idle and active controlled profiling remains a release gate; no performance-improvement claim is made.

## Remaining public-release gates

- Controlled idle/active profiling and full normal/slowed motion review, including hover and interrupted transitions.
- Real VoiceOver walkthrough, light/dark checks on all pages, and system accessibility override checks beyond unit coverage.
- Login registration/reboot verification and missing-Codex installation on a clean account/Mac.
- Developer ID signing, hardened-runtime runtime validation, notarization, and Gatekeeper installation on another Mac.
- Final source/license/security review and explicit authorization to create/push/publish the GitHub repository.

Local artifacts are unnotarized. No automatic updater, Intel build, notification feature, or project filtering is included.

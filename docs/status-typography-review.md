# Status typography pass

Scope: compact rail, hover tray, expanded primary activity, and recent/secondary task rows. Native SwiftUI adaptation of Better Typography; existing rail customization is preserved.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| Medium | `Sources/CodexIsland/IslandView.swift`, `TrayActivityText.swift` | Tray status inherited inconsistent system/Inter Tight fonts and 10–11 pt sizes | One explicit Inter Tight Regular 12 pt status role | Consistent readable hierarchy and a real bundled font weight |
| Low | `Sources/CodexIsland/CompactStatusFlip.swift` | Arbitrary 0.15 pt tracking and independent white styling | Natural font kerning and the shared status treatment | Preserve letterforms and avoid surface-specific styling |
| Low | `Sources/CodexIsland/IslandView.swift`, `TrayMetadata.swift`, `TrayActivityText.swift` | Small tray text felt densely packed at native sizes | Shared 0.18 pt tracking for metadata, quota, counters, recency, and tray statuses; ticker cells include that width | User-requested optical breathing room without altering headings, rail typography, or island width |
| Medium | `Sources/CodexIsland/TrayActivityText.swift`, `CompactStatusFlip.swift` | Only primary tray status shimmered | Shared horizontal, absolute-time 2.5 s shimmer on all visible working labels | Consistent feedback, including rail flips and task rows |

Status labels stay single-line with accessible descriptions and help text. The rail retains its Nunito/system font, size, and weight preferences. Idle remains text-free. Failure, attention, completion, and cancellation are deliberately static; warnings retain semantic color. Reduce Motion and disabled animations stop shimmer; Increased Contrast uses white text rather than a gray gradient.

Verification: 128 tests pass, including every state/compact alias and hidden, disabled, and reduced-motion shimmer policies. Release bundle builds successfully. Inspected synthetic hover and multi-chat tray renders for label wrapping/overlap. Captured 155 app-only synthetic motion samples at normal and slowed playback timing; this is not a frame-rate measurement.

Not verified: full VoiceOver traversal and normal/slowed playback review of the complete recording. No measured performance claim is made.

Verdict: **Approve**, limited to inspected status typography and tested shimmer policy.

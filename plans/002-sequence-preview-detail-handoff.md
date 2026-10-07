# 002 — Sequence the preview-to-detail content handoff

- **Status**: IMPLEMENTED — tests, release build, installation, and endpoint visuals verified; live slow-motion feel-check pending
- **Commit**: unavailable — this checkout has no `HEAD` (`git rev-parse --short HEAD` failed); do not initialize Git
- **Severity**: MEDIUM
- **Category**: Cohesion, physicality, interruptibility
- **Estimated scope**: 3 files, approximately 100 lines
- **Dependency**: execute plan 001 first; both changes must be reviewed together on the installed app

## Problem

`Sources/CodexIsland/IslandView.swift:35-49` always builds both preview and expanded content in the same `ZStack` and crossfades them with complementary progress values:

```swift
preview
    .frame(width: motion.layout.previewFrame.width - 2 * motion.layout.shoulderReach,
           height: 116, alignment: .top)
    .opacity(max(0, min(1, motion.progress)) * max(0, 2 - motion.progress))
    .allowsHitTesting(model.presentation == .preview)
    .accessibilityHidden(model.presentation != .preview || motion.progress < 0.95)
    .disabled(model.presentation != .preview)
expanded
    .frame(width: motion.layout.expandedFrame.width - 2 * motion.layout.shoulderReach,
           height: motion.layout.expandedFrame.height - topHeight)
    .opacity(max(0, min(1, motion.progress - 1)))
    .allowsHitTesting(model.presentation == .pinned)
    .accessibilityHidden(model.presentation != .pinned || motion.progress < 1.98)
    .disabled(model.presentation != .pinned)
```

At progress 1.5, both content layers have 50% opacity and occupy the same top region. That can double-expose titles and controls. A direct compact-to-pinned click also briefly displays preview content while the shape passes through progress 1, even though the user did not request a preview. The body already has stable layout widths and a single sampled spring; add no second animator.

## Target

Derive content opacity and a tiny compositing offset from `motion.progress`; do not create independent animations. Extract pure `IslandContentReveal` calculations in `Sources/CodexIsland/IslandMotion.swift` so tests can exercise them without a window. Use exact progress windows below; `clamp01(x) = min(1, max(0, x))`.

```swift
previewOpacity(p, eligible):
    if !eligible: 0
    if p <= 1: clamp01((p - 0.12) / 0.78)
    else: 1 - clamp01((p - 1.10) / 0.35)

expandedOpacity(p, eligible):
    if eligible: clamp01((p - 1.32) / 0.48)  // pin from a real hover preview
    else:        clamp01((p - 0.90) / 0.75)  // direct compact pin, or pinned dismissal

previewYOffset(p, opacity):
    if p <= 1:  6 * (1 - opacity) points
    else:      -4 * (1 - opacity) points

expandedYOffset(opacity): 6 * (1 - opacity) points
```

The slight offsets are compositing transforms, not layout changes. They give the content a physical arrival from the notch while the panel itself grows. On Reduce Motion or when app animations are off, set both offsets to zero; keep the existing short opacity feedback. No blur is necessary unless slow-motion inspection still shows double exposure. The compact rail must remain fully visible throughout.

Track one coordinator-owned `previewContentEligible` Boolean. It is `true` while targeting preview, remains `true` when pinning from any visible preview (`previousTarget == 1 && spring.value > 0.12`), and remains `true` during preview-to-compact hover exit. It is `false` for direct compact-to-pinned clicks and pinned-to-compact dismissal. Clear it after settling in compact. A route change may alter opacity, but must never reset `spring.value` or `spring.velocity`. Using the opacity onset rather than a later threshold avoids instantly hiding preview content on an early click.

While the expanded layer is not meaningfully visible (`expandedOpacity < 0.95`), it must not receive pointer clicks or keyboard focus. The preview remains clickable during its eligible transition so an early click still pins. VoiceOver exposure should follow the visible active layer, not merely the target presentation enum.

## Repo conventions to follow

- `Sources/CodexIsland/IslandMotion.swift:15-79` owns presentation progress and already publishes it to SwiftUI. Extend that coordinator; do not add a timer, animation driver, or implicit `.animation` around the entire `ZStack`.
- `Sources/CodexIsland/IslandView.swift:37,44` already fixes content at final-stage widths, preventing text rewrap during panel resizing. Keep those width constraints.
- `Sources/CodexIsland/IslandView.swift:10` and `Sources/CodexIsland/IslandMotion.swift:5-10` already resolve Reduce Motion and app animation-off; use them rather than introducing a separate preference.
- `Sources/CodexIsland/IslandDesign.swift:23-24` contains the existing short label and press durations. Do not slow them or add decorative stagger to high-frequency controls.

## Steps

1. Add pure, internal `IslandContentReveal` static functions to `Sources/CodexIsland/IslandMotion.swift`, implementing the exact opacity and offset formulas above. Return zero offset when the caller passes `movementAllowed == false`; the caller passes `model.animationsEnabled && !reduceMotion`.
2. Add `@Published private(set) var previewContentEligible = false` to `IslandMotionCoordinator`. In `update(layout:state:policy:)`, capture the old `spring.target` and `spring.value` before assigning the new target. On a target change: target 1 sets eligibility true; target 2 sets it to `(oldTarget == 1 && oldValue > 0.12)`; target 0 sets it to `(oldTarget == 1)`. If policy is reduced or immediate, use the final target geometry exactly as today; eligibility affects content only. When the full-motion spring settles at target 0, clear eligibility after publishing the final progress.
3. In `IslandView.swift:35-49`, compute local `previewOpacity` and `expandedOpacity` from the helper and `motion.previewContentEligible`; replace the existing opacity formulas. Apply `.offset(y:)` with the helper after each fixed `.frame` and before `.opacity`, without changing frame dimensions or the `ZStack` structure. Keep `.opacity(motion.contentOpacity)` on the body.
4. Keep preview hit testing tied to `model.presentation == .preview` so a click during hover expansion can pin. Gate expanded hit testing and `.disabled` with `model.presentation == .pinned && expandedOpacity >= 0.95`. Change each `.accessibilityHidden` to follow that layer's computed visibility and presentation route. In `iconButton` at `IslandView.swift:374-381`, add the same expanded-visibility gate to `focusRequested`; immediate/reduced policy reaches final progress synchronously, so it still grants focus promptly.
5. Add tests in `Tests/CodexIslandTests/CodexIslandTests.swift` for both routes: hover preview appears by progress 0.90; preview is absent for direct compact pin; preview fades to zero by 1.45 when pinning from preview; expanded detail reaches full opacity by 1.80 from preview or 1.65 directly; at every 0.01 progress increment from 1.10 through 1.80, the lower of the two opacities stays below 0.20; reduced/disabled motion yields zero offsets. Test coordinator eligibility through preview→pinned, compact→pinned, preview→compact, pinned→compact, and reversal without resetting spring progress/velocity. Include an early preview click at progress approximately 0.3 and assert its preview opacity is continuous across the route change.

## Boundaries

- Do not modify `IslandSpring` timing, `IslandLayout` geometry from plan 001, cube animation, quota animation, or data polling.
- Do not animate font size, layout width/height, or the whole status rail. Do not add an always-running driver.
- Preserve the 120 ms hover intent delay, 220 ms exit grace, dismissal suppression, keyboard focus after pinning, and click-through outside the visible contour.
- Do not add blur as a default effect; it is a fallback only if actual slow-motion review proves necessary.
- If the cited code has materially changed, stop and report drift rather than improvising from this plan.

## Verification

- **Mechanical**: run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/codex-island-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/codex-island-module-cache xcrun swift test --disable-sandbox` and the release build with `xcrun swift build --disable-sandbox -c release`; expect exit 0 and all existing tests retained.
- **Feel check**: on the built-in display, hover to preview then pin, click compact directly to pin, dismiss with Escape, dismiss by outside click, and reverse a hover exit by re-entering. Review slowly or frame-by-frame: there should be no two readable titles layered together, no brief preview title on direct pin, no blank-looking stall, no snap in content position, and no invisible expanded control accepting a click. Check the stable cube/ring rail during every path.
- **Accessibility**: enable Reduce Motion and confirm offsets disappear while short opacity feedback remains; turn app animations off and confirm content snaps with the panel. Use keyboard navigation after pinning to confirm focus lands on a visible control, then Escape to dismiss.
- **Installed check**: after both plans are implemented, run `./scripts/install-dev.sh`, confirm `launchctl print gui/$(id -u)/com.codexisland.app` reports `state = running`, and inspect `/tmp/codex-island.log` for startup errors. Do not claim frame-rate improvements without measuring them.
- **Done when**: all route and overlap tests pass, the live handoff shows one readable content layer at a time, direct pin skips preview content, and the behavior remains reversible and accessible.

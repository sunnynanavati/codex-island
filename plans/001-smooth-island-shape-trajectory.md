# 001 — Smooth the island shape trajectory

- **Status**: IMPLEMENTED — tests, release build, installation, and endpoint visuals verified; live slow-motion feel-check pending
- **Commit**: unavailable — this checkout has no `HEAD` (`git rev-parse --short HEAD` failed); do not initialize Git
- **Severity**: HIGH
- **Category**: Physicality, interruptibility, cohesion
- **Estimated scope**: 2 files, approximately 70 lines

## Problem

`Sources/CodexIsland/Presentation.swift:129` linearly interpolates each half of the three-stage presentation independently:

```swift
func frame(at progress: Double) -> CGRect {
    let p = min(2, max(0, progress))
    let a = p <= 1 ? compactFrame : previewFrame
    let b = p <= 1 ? previewFrame : expandedFrame
    let t = p <= 1 ? p : p - 1
    return CGRect(x: a.minX + (b.minX - a.minX) * t,
                  y: a.minY + (b.minY - a.minY) * t,
                  width: a.width + (b.width - a.width) * t,
                  height: a.height + (b.height - a.height) * t)
}
```

`Sources/CodexIsland/Presentation.swift:109-124` originally made the preview body width `max(392, width)`. At the default compact body width of 418 points, preview width was also 418 and pinned width was 456. Width therefore stood still from progress 0 to 1, then started moving at progress 1. At a 38-point safe top inset, height advanced 116 points in the first stage and 326 in the second: its velocity changed abruptly at progress 1 even though `IslandSpring` was continuous. A direct compact-to-pinned click traversed this seam.

## Target

Preserve the current compact and pinned dimensions, notch clearance, screen clamping, calibrated position/width/shoulders, and the single interruptible spring in `IslandMotionCoordinator`. Set the preview body width halfway between compact and pinned body widths, so default widths are **418 → 437 → 456 points**. Keep preview height `compactHeight + 116` and pinned height `compactHeight + 442`.

Replace the two independent linear segments with a coordinate-wise, monotone cubic Hermite mapping through all three frames. For each coordinate `a` (compact), `b` (preview), `c` (pinned), define `d0 = b - a`, `d1 = c - b`, and midpoint tangent `m = 0` when `d0 * d1 <= 0`, otherwise `m = 2 * d0 * d1 / (d0 + d1)`. Use tangents `(d0, m)` on progress `[0,1]` and `(m, d1)` on `[1,2]`. The Hermite segment at local `t` is:

```swift
let t2 = t * t, t3 = t2 * t
return (2*t3 - 3*t2 + 1)*v0 + (t3 - 2*t2 + t)*s0
     + (-2*t3 + 3*t2)*v1 + (t3 - t2)*s1
```

Interpolate `minX`, `width`, and `height`; set `minY = compactFrame.maxY - interpolatedHeight`, preserving the fixed screen-top edge. This makes both value and velocity continuous at the preview waypoint. The existing spring, not a second animation, remains responsible for timing and reversals. No bounce or new looping motion.

## Repo conventions to follow

- `Sources/CodexIsland/Presentation.swift:145-160` already defines the critically damped `IslandSpring`; leave its parameters and current velocity handoff intact.
- `Sources/CodexIsland/IslandMotion.swift:36-79` drives frame, corner, and content progress from one display link. Do not add another driver or an independent SwiftUI spring.
- `Sources/CodexIsland/IslandPanelController.swift:45-50` updates the actual window frame and mask from the sampled frame. Keep this path and hit-region correspondence.
- Preserve the Reduce Motion and animation-off policies in `Sources/CodexIsland/IslandMotion.swift:5-10,42-54`.

## Steps

1. In `IslandLayout.calculate` (`Sources/CodexIsland/Presentation.swift`), compute `expandedBodyWidth = max(456, width)` and `previewBodyWidth = width + (expandedBodyWidth - width) / 2`. Use those values for `previewFrame` and `expandedFrame` instead of `max(392, width)` and `max(456, width)`. Retain the existing `frame(width:height:)` clamp and `2 * shoulderReach` additions.
2. In `IslandLayout.frame(at:)`, replace the two-piece linear interpolation with the exact cubic Hermite mapping above. Use one private scalar helper inside `IslandLayout` for `minX`, `width`, and `height`, clamp input progress to `[0,2]`, and return the exact stored endpoint frames for `p == 0`, `p == 1`, and `p == 2` to avoid accumulated floating-point drift. Do not interpolate the screen-top `maxY` independently.
3. In `Tests/CodexIslandTests/CodexIslandTests.swift`, extend `testLayoutCalculations` to assert preview body width is halfway between compact and pinned body widths. With its current calibration, expect `layout.previewFrame.width == 647` and `layout.bodyWidth(at: 1) == 447` (compact 438, pinned 456, shoulders 100 each).
4. Add a geometry test using `epsilon = 0.0001` around progress 1. For `minX`, `width`, and `height`, compare left and right finite-difference slopes with tolerance `0.1` point per progress unit. Also sample progress from 0 through 2 in `0.01` increments and assert width and height stay within endpoint bounds and `maxY` remains the screen top. Retain the existing screen-clamp and hit-region tests.

## Boundaries

- Do not change the notch contour path, cube timing, quota ring, data monitoring, UI copy, hover delays, or keyboard behavior.
- Do not add a spring, timer, third-party dependency, or persistent preference.
- Do not replace the real window resize with a visual-only scale transform: hit testing and the transparent corners must continue to match the visible surface.
- If the cited code has materially changed, stop and report drift rather than improvising from this plan.

## Verification

- **Mechanical**: run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/codex-island-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/codex-island-module-cache xcrun swift test --disable-sandbox`; expect all tests to pass. Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/tmp/codex-island-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/codex-island-module-cache xcrun swift build --disable-sandbox -c release`; expect exit 0.
- **Feel check**: on the built-in notched display, hover from compact to preview, click from preview to pin, click directly from compact to pin, and interrupt each expansion with dismissal. Record at high frame rate or review slowly: width and height should keep changing smoothly through the preview waypoint, with no catch-up or velocity kink. Verify the shoulder curve and clickable region stay aligned at intermediate frames.
- **Accessibility**: enable macOS Reduce Motion and confirm frame changes remain immediate with the existing short opacity transition; disable app animations and confirm no driver remains active.
- **Done when**: endpoint dimensions are preserved except for the intentional preview width, intermediate frames stay within the screen, slope continuity tests pass, reversals remain continuous, and manual slow-motion review shows no mid-transition speed change.

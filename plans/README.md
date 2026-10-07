# Codex Island motion plans

These plans were implemented as one coordinated pass. The source and installed app have been updated. Automated and endpoint-visual checks passed; a live slow-motion transition review remains pending because the available UI control could not capture intermediate hover frames.

| Order | Plan | Severity | Status |
| --- | --- | --- | --- |
| 1 | [001 — Smooth the island shape trajectory](001-smooth-island-shape-trajectory.md) | HIGH | IMPLEMENTED; feel-check pending |
| 2 | [002 — Sequence the preview-to-detail content handoff](002-sequence-preview-detail-handoff.md) | MEDIUM | IMPLEMENTED; feel-check pending |

001 was implemented before 002 because 002's reveal windows are keyed to the same presentation progress. All 39 tests passed; the release build and development installer succeeded; the LaunchAgent is running with a successful-refresh log. Live compact and pinned views and the synthetic preview endpoint were inspected. The remaining check is to watch the hover and click trajectories on the built-in display, including an early click during hover, and report any perceived timing or overlap issue. The existing single spring, stable cubes, Reduce Motion behavior, and click-through contour remain in place. This checkout has no Git `HEAD`; do not initialize a repository merely to stamp the plans.

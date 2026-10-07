import AppKit
import XCTest
@testable import CodexIsland

final class SettingsLayoutTests: XCTestCase {
    @MainActor
    func testMaximumTypographyFitsBothFontsAndChatCounts() {
        IslandFont.register()
        for family in IslandFontFamily.allCases {
            for count in [1, 3] {
                var preferences = IslandPreferences()
                preferences.fontFamily = family
                preferences.typography = .init(statusSize: 14, statusWeight: .semibold,
                                               quotaSize: 10.5, quotaWeight: .semibold)
                preferences.statusGap = 16
                preferences.ringStroke = 1.8
                for label in ["Thinking", "Searching", "Attention", "Your turn"] {
                    let font = IslandFont.nsFont(weight: .semibold, size: 14, family: family)
                    let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
                    let wing = PanelController.compactWingWidth(cubeCount: count, statusLabel: label,
                                                               typography: preferences.typography,
                                                               preferences: preferences)
                    let layout = syntheticLayout(preferences, wing: wing)
                    let availableWing = (layout.bodyWidth(at: 0) - layout.notchGapWidth) / 2
                        - CompactRailSizing.railInset
                    let group = textWidth + preferences.statusGap + CompactQuotaRing.diameter
                    XCTAssertGreaterThanOrEqual(availableWing - group,
                                                2 * CompactRailSizing.statusSideInset - 0.001,
                                                "\(family) / \(label) / \(count) cubes")
                    XCTAssertGreaterThanOrEqual(CubeTimeline.visibleCount(total: count, wingWidth: availableWing), count)
                    XCTAssertLessThanOrEqual(CompactQuotaRing.diameter + preferences.ringStroke,
                                             layout.compactFrame.height - 8)
                    XCTAssertEqual(layout.notchGapWidth, 192)
                    XCTAssertLessThanOrEqual(layout.compactFrame.width, layout.previewFrame.width)
                    preferences.calibration.compactSize = 1
                    let maximum = syntheticLayout(preferences, wing: wing)
                    XCTAssertEqual(maximum.compactFrame.width, maximum.previewFrame.width, accuracy: 0.001)
                    XCTAssertEqual(maximum.previewFrame.width, layout.previewFrame.width, accuracy: 0.001)
                    preferences.calibration.compactSize = 0
                }
            }
        }
    }

    @MainActor
    func testStoppedMotionCanResumeAndImmediatelySettle() {
        let layout = syntheticLayout(.init(), wing: 120)
        let coordinator = IslandMotionCoordinator(layout: layout)
        let view = NSView(frame: layout.compactFrame)
        coordinator.attach(to: view)
        coordinator.update(layout: layout, state: .pinned, policy: .full)
        coordinator.advance(by: 0.03)
        let interrupted = coordinator.progress
        XCTAssertGreaterThan(interrupted, 0)
        XCTAssertLessThan(interrupted, 2)
        coordinator.stop()
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.progress, interrupted)
        coordinator.update(layout: layout, state: .compact, policy: .immediate)
        XCTAssertEqual(coordinator.frame, layout.compactFrame)
        XCTAssertFalse(coordinator.isRunning)
        coordinator.update(layout: layout, state: .preview, policy: .reduced)
        XCTAssertEqual(coordinator.frame, layout.previewFrame)
        coordinator.stop()
        XCTAssertFalse(coordinator.isRunning)
    }

    @MainActor
    func testMotionSpeedChangesTravelWithoutChangingDestination() {
        let layout = syntheticLayout(.init(), wing: 120)
        let slower = IslandMotionCoordinator(layout: layout)
        let faster = IslandMotionCoordinator(layout: layout)
        slower.speed = 0.8
        faster.speed = 1.2
        for coordinator in [slower, faster] {
            coordinator.update(layout: layout, state: .pinned, policy: .full)
            coordinator.advance(by: 0.03)
        }
        XCTAssertGreaterThan(faster.progress, slower.progress)
        for _ in 0..<200 {
            slower.advance(by: 1.0 / 60)
            faster.advance(by: 1.0 / 60)
        }
        XCTAssertEqual(slower.frame, layout.expandedFrame)
        XCTAssertEqual(faster.frame, layout.expandedFrame)
    }

    func testConfiguredBlurStaysBoundedAndFadeNeverFolds() {
        for peak in [0.0, 1.5, 3.0] {
            for step in 0...100 {
                for entering in [true, false] {
                    let progress = Double(step) / 100
                    let fold = StatusFlipFrame(progress: progress, entering: entering,
                                               reduceMotion: false, peakBlur: peak)
                    XCTAssertGreaterThanOrEqual(fold.blurRadius, 0)
                    XCTAssertLessThanOrEqual(fold.blurRadius, peak)
                    let fade = StatusFlipFrame(progress: progress, entering: entering,
                                               reduceMotion: true, peakBlur: peak)
                    XCTAssertEqual(fade.blurRadius, 0)
                    XCTAssertEqual(fade.verticalScale, 1)
                    XCTAssertEqual(fade.alpha, entering ? progress : 1 - progress, accuracy: 0.0001)
                }
            }
        }
    }

    private func syntheticLayout(_ preferences: IslandPreferences, wing: CGFloat) -> IslandLayout {
        IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                               safeTopInset: 32, leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                               calibration: preferences.calibration, compactWingWidth: wing)
    }
}

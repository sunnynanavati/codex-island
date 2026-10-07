import AppKit
import XCTest
@testable import CodexIsland

final class TrayPolishTests: XCTestCase {
    @MainActor func testPinnedShoulderEasesDeeperWithoutChangingCompactOrHoverDepth() {
        let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                            safeTopInset: 32, leftAuxiliaryMaxX: 666, rightAuxiliaryMinX: 846,
                                            calibration: .init(waveReach: 61))
        let motion = IslandMotionCoordinator(layout: layout)
        XCTAssertEqual(motion.shoulderHeight, 32)
        motion.update(layout: layout, state: .preview, policy: .immediate)
        XCTAssertEqual(motion.shoulderHeight, 32)
        motion.update(layout: layout, state: .pinned, policy: .full)
        let start = motion.shoulderHeight
        motion.advance(by: 1.0 / 60)
        XCTAssertGreaterThan(motion.shoulderHeight, start)
        XCTAssertLessThan(motion.shoulderHeight, 48)
        for _ in 0..<180 { motion.advance(by: 1.0 / 60) }
        XCTAssertEqual(motion.shoulderHeight, 48)
        XCTAssertFalse(motion.isRunning)
        motion.update(layout: layout, state: .compact, policy: .immediate)
        XCTAssertEqual(motion.shoulderHeight, 32)
        XCTAssertEqual(motion.layout.compactShoulderReach, 61)
    }

    @MainActor func testOnlyEmptyActivityPageUsesShortHeight() {
        let model = AppModel(fixture: IslandFixtures.snapshot("idle"))
        XCTAssertEqual(model.expandedBodyHeight, 222)
        var updates = 0
        model.onLayoutChange = { updates += 1 }
        model.page = .recent
        XCTAssertEqual(model.expandedBodyHeight, 398)
        XCTAssertEqual(updates, 1)
        model.page = .activity
        for scenario in ["active", "multiple", "attention", "failed", "error"] {
            model.setFixture(IslandFixtures.snapshot(scenario))
            XCTAssertEqual(model.expandedBodyHeight, 398, scenario)
        }
        model.setFixture(IslandFixtures.snapshot("idle"))
        XCTAssertEqual(model.expandedBodyHeight, 222)
    }

    func testDailySummaryUsesCompletedTurnsAndReadableDuration() {
        let summary = DailySummary(stats: .init(completedTurns: 41, activeDuration: 600))
        XCTAssertEqual(summary.turns, "41 turns")
        XCTAssertEqual(summary.duration, "10 mins")
        XCTAssertEqual(summary.sentence, "You completed 41 turns today and were active for about 10 mins.")
        let single = DailySummary(stats: .init(completedTurns: 1, activeDuration: 60))
        XCTAssertEqual(single.turns, "1 turn")
        XCTAssertEqual(single.duration, "1 min")
        XCTAssertEqual(DailySummary(stats: .init(completedTurns: 0, activeDuration: 30)).duration, "less than 1 min")
        XCTAssertEqual(DailySummary(stats: .init(completedTurns: 0, activeDuration: 3660)).duration, "1 hr 1 min")
    }

    func testDailySummaryHandlesInvalidStats() {
        XCTAssertEqual(DailySummary(stats: .init(completedTurns: -1, activeDuration: .infinity)).turns, "0 turns")
        XCTAssertEqual(DailySummary(stats: .init(completedTurns: 0, activeDuration: -60)).duration, "0 mins")
        XCTAssertEqual(DailySummary(stats: .init(completedTurns: 0, activeDuration: 100_000)).duration, "24 hrs")
    }

    @MainActor func testPinnedHeightRetargetPreservesFrameVelocityAndTopAnchor() {
        func layout(_ height: CGFloat) -> IslandLayout {
            IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                   safeTopInset: 32, leftAuxiliaryMaxX: 666, rightAuxiliaryMinX: 846, calibration: .init(),
                                   railGeometry: .init(cubeWidth: 22, statusWidth: 22, clearance: 12),
                                   expandedBodyHeight: height)
        }
        let full = layout(398), idle = layout(222)
        let motion = IslandMotionCoordinator(layout: full)
        motion.update(layout: full, state: .pinned, policy: .immediate)
        motion.update(layout: idle, state: .pinned, policy: .full)
        XCTAssertEqual(motion.frame, full.expandedFrame)
        for _ in 0..<5 { motion.advance(by: 1.0 / 60) }
        let frame = motion.frame, velocity = motion.expandedHeightSpring.velocity
        XCTAssertLessThan(frame.height, full.expandedFrame.height)
        XCTAssertEqual(frame.maxY, full.expandedFrame.maxY, accuracy: 0.001)
        motion.update(layout: full, state: .pinned, policy: .full)
        XCTAssertEqual(motion.frame, frame)
        XCTAssertEqual(motion.expandedHeightSpring.velocity, velocity)
        for _ in 0..<180 { motion.advance(by: 1.0 / 60) }
        XCTAssertEqual(motion.frame, full.expandedFrame)
        motion.update(layout: idle, state: .pinned, policy: .reduced)
        XCTAssertEqual(motion.frame, idle.expandedFrame)
        motion.update(layout: full, state: .pinned, policy: .immediate)
        XCTAssertEqual(motion.frame, full.expandedFrame)
        XCTAssertFalse(motion.isRunning)
    }
}

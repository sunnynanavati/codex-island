import AppKit
import XCTest
@testable import CodexIsland

final class RailPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ states: [(String, ActivityState)], at time: Date? = nil) -> IslandSnapshot {
        let time = time ?? now
        let tasks = states.map { id, state in
            TaskSnapshot(id: id, title: "Synthetic chat", workspacePath: nil, rolloutPath: nil,
                         state: state, updatedAt: time, startedAt: now, completedTurns: [],
                         activityIntervals: [], pendingQuestion: nil, quota: nil,
                         isChildAgent: false, agentCount: 1, error: nil)
        }
        return IslandSnapshot(tasks: tasks, primaryTaskID: states.first?.0, dailyStats: .init(completedTurns: 0, activeDuration: 0),
                              quota: nil, refreshedAt: time, errorMessage: nil)
    }

    @MainActor func testIdleNeverReservesReadyOrDoneTextAndHistoricalCompletionDoesNotReplay() {
        var rail = RailPresentation()
        for state in [ActivityState.idle, .completed, .cancelled] {
            rail.update(snapshot: snapshot([("chat", state)]), now: now)
            XCTAssertNil(rail.label)
            XCTAssertNil(rail.sizingLabel)
            XCTAssertFalse(rail.usesWorkingWidth)
            XCTAssertNil(rail.completionDeadline)
            XCTAssertEqual(rail.cubes.count, 1)
            XCTAssertEqual(rail.cubes[0].state, .idle)
            XCTAssertEqual(rail.cubes[0].solvedColor, 0)
        }
    }

    @MainActor func testFinishedPeersKeepTheirPositionsUntilFinalCompletion() {
        var rail = RailPresentation()
        rail.update(snapshot: snapshot([("a", .thinking), ("b", .editing)]), now: now)
        let identities = rail.cubes.map(\.id)
        rail.update(snapshot: snapshot([("b", .editing), ("a", .completed)], at: now.addingTimeInterval(1)),
                    now: now.addingTimeInterval(1))
        rail.update(snapshot: snapshot([("a", .completed), ("b", .running)], at: now.addingTimeInterval(60)),
                    now: now.addingTimeInterval(60))
        XCTAssertEqual(rail.cubes.map(\.id), identities)
        XCTAssertEqual(rail.cubes[0].solvedColor, 0)
        XCTAssertEqual(rail.label, "Running")
        XCTAssertNil(rail.completionDeadline)
        let finish = now.addingTimeInterval(61)
        rail.update(snapshot: snapshot([("a", .completed), ("b", .completed)], at: finish), now: finish)
        XCTAssertNil(rail.label)
        XCTAssertEqual(rail.sizingLabel, "Running")
        XCTAssertEqual(rail.cubes.map(\.solvedColor), [0, 1])
        rail.settle(at: finish.addingTimeInterval(0.48))
        XCTAssertTrue(rail.usesWorkingWidth)
        rail.settle(at: finish.addingTimeInterval(0.49))
        XCTAssertFalse(rail.usesWorkingWidth)
        XCTAssertEqual(rail.cubes.count, 1)
        XCTAssertEqual(rail.cubes[0].solvedColor, 0)
    }

    @MainActor func testNewWorkCancelsFinalContractionAndKeepsAnimationPhase() {
        var rail = RailPresentation()
        rail.update(snapshot: snapshot([("a", .thinking)]), now: now)
        rail.update(snapshot: snapshot([("a", .completed)]), now: now.addingTimeInterval(1))
        let deadline = rail.completionDeadline!
        rail.update(snapshot: snapshot([("a", .editing)]), now: now.addingTimeInterval(1.2))
        let epoch = rail.cubes[0].epoch
        rail.settle(at: deadline)
        rail.update(snapshot: snapshot([("a", .running)]), now: now.addingTimeInterval(2))
        XCTAssertEqual(rail.cubes[0].epoch, epoch)
        XCTAssertNil(rail.completionDeadline)
        XCTAssertNil(rail.cubes[0].solvedColor)
        XCTAssertEqual(rail.label, "Running")
    }

    @MainActor func testSubagentsUseRootIdentityAndHistoricalTasksDoNotJoinWorkingRoster() {
        var value = snapshot([("root", .thinking), ("child", .editing), ("old", .completed)])
        value.tasks[1].isChildAgent = true
        value.tasks[1].rootChatID = "root"
        var rail = RailPresentation()
        rail.update(snapshot: value, now: now)
        XCTAssertEqual(rail.cubes.map(\.id), ["root"])
    }

    @MainActor func testAttentionAndFailureRemainVisibleWhileCancellationCompacts() {
        for state in [ActivityState.waitingForInput, .attentionRequired, .failed] {
            var rail = RailPresentation()
            rail.update(snapshot: snapshot([("a", state)]), now: now)
            XCTAssertNotNil(rail.label)
            XCTAssertTrue(rail.usesWorkingWidth)
        }
        var rail = RailPresentation()
        rail.update(snapshot: snapshot([("a", .thinking)]), now: now)
        rail.update(snapshot: snapshot([("a", .cancelled)]), now: now.addingTimeInterval(1))
        XCTAssertFalse(rail.usesWorkingWidth)
        XCTAssertNil(rail.completionDeadline)
    }

    @MainActor func testDisabledCompletionAnimationSettlesWithoutDeadline() {
        var rail = RailPresentation()
        rail.update(snapshot: snapshot([("a", .thinking)]), now: now)
        rail.update(snapshot: snapshot([("a", .completed)]), now: now, completionAnimated: false)
        XCTAssertFalse(rail.usesWorkingWidth)
        XCTAssertNil(rail.completionDeadline)
        XCTAssertEqual(rail.cubes[0].state, .idle)
    }

    func testPhysicalPixelClearanceAndOverflowMeasurement() {
        XCTAssertEqual(RailGeometry.clearance(displayScale: 1), 24)
        XCTAssertEqual(RailGeometry.clearance(displayScale: 2), 12)
        XCTAssertEqual(RailGeometry.cubeWidth(count: 1), 22)
        XCTAssertEqual(RailGeometry.cubeWidth(count: 3), 78)
        XCTAssertGreaterThan(RailGeometry.cubeWidth(count: 4), 78)
        XCTAssertGreaterThan(RailGeometry.cubeWidth(count: 1000), RailGeometry.cubeWidth(count: 4))
    }

    func testScreenClampingAndPositionCalibrationPreserveNotchClearance() {
        for screenWidth: CGFloat in [800, 1512] {
            for offset in [-120.0, 0, 120] {
                let geometry = RailGeometry(cubeWidth: 78, statusWidth: 100, clearance: 12)
                let center = screenWidth / 2
                let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: screenWidth, height: 982),
                                                    safeTopInset: 32, leftAuxiliaryMaxX: center - 96,
                                                    rightAuxiliaryMinX: center + 96,
                                                    calibration: .init(horizontalOffset: offset, waveReach: 220),
                                                    railGeometry: geometry)
                for step in 0...100 {
                    let frame = layout.frame(at: Double(step) / 50)
                    XCTAssertGreaterThanOrEqual(frame.minX, 0)
                    XCTAssertLessThanOrEqual(frame.maxX, screenWidth + 0.001)
                    XCTAssertEqual(frame.maxY, 982)
                }
                XCTAssertEqual(layout.notchGapWidth, 192 + 2 * abs(offset))
                XCTAssertGreaterThanOrEqual(layout.bodyWidth(at: 0), layout.notchGapWidth + 2 * geometry.wingWidth - 0.001)
            }
        }
    }

    @MainActor func testSymmetricIdleSizingIgnoresManualExpansionAndProtectsMaximumType() {
        IslandFont.register()
        var preferences = IslandPreferences()
        preferences.calibration.compactSize = 1
        preferences.calibration.adaptiveWidth = false
        preferences.calibration.widthAdjustment = 120
        let idleGeometry = PanelController.railGeometry(cubeCount: 1, label: nil,
                                                       typography: preferences.typography, preferences: preferences, displayScale: 2)
        let idle = layout(idleGeometry, preferences.calibration, working: false)
        XCTAssertEqual(idle.bodyWidth(at: 0), 192 + 2 * idleGeometry.wingWidth, accuracy: 0.001)
        XCTAssertLessThan(idle.compactFrame.width, idle.previewFrame.width)
        XCTAssertEqual(idle.compactFrame.midX, 756)
        for font in IslandFontFamily.allCases {
            preferences.fontFamily = font
            preferences.typography.statusSize = 14
            preferences.statusGap = 16
            preferences.ringStroke = 1.8
            for count in [1, 3, 5] {
                let geometry = PanelController.railGeometry(cubeCount: count, label: "Attention",
                                                            typography: preferences.typography, preferences: preferences, displayScale: 2)
                let active = layout(geometry, .init(), working: true)
                let wing = (active.bodyWidth(at: 0) - active.notchGapWidth) / 2
                XCTAssertGreaterThanOrEqual((wing - geometry.cubeWidth) / 2, 12 - 0.001)
                XCTAssertGreaterThanOrEqual((wing - geometry.statusWidth) / 2, 12 - 0.001)
                XCTAssertEqual(active.compactFrame.midX, idle.compactFrame.midX)
            }
        }
    }

    @MainActor func testMotionRetargetsRingAndWidthTogetherWithoutJumps() {
        let idle = layout(.init(cubeWidth: 22, statusWidth: 21.2, clearance: 12))
        let active = layout(.init(cubeWidth: 78, statusWidth: 100, clearance: 12))
        let motion = IslandMotionCoordinator(layout: idle)
        motion.update(layout: active, state: .preview, policy: .full)
        for _ in 0..<6 { motion.advance(by: 1.0 / 60) }
        let frame = motion.frame
        let statusWidth = motion.statusWidthSpring.value
        let velocity = motion.widthSpring.velocity
        motion.update(layout: idle, state: .compact, policy: .full)
        XCTAssertEqual(motion.frame.width, frame.width, accuracy: 0.001)
        XCTAssertEqual(motion.statusWidthSpring.value, statusWidth)
        XCTAssertEqual(motion.widthSpring.velocity, velocity)
        for _ in 0..<180 { motion.advance(by: 1.0 / 60) }
        XCTAssertEqual(motion.frame, idle.compactFrame)
        XCTAssertFalse(motion.isRunning)
        motion.update(layout: active, state: .pinned, policy: .immediate)
        XCTAssertEqual(motion.frame, active.expandedFrame)
        XCTAssertFalse(motion.isRunning)
        motion.update(layout: idle, state: .pinned, policy: .reduced)
        XCTAssertEqual(motion.progress, 2)
        XCTAssertEqual(motion.statusWidthSpring.value, idle.railGeometry!.statusWidth)
        motion.stop()
    }

    @MainActor func testLastCollapsePixelsRemainInsideContinuousShoulder() {
        let layout = layout(.init(cubeWidth: 22, statusWidth: 21.2, clearance: 12))
        let motion = IslandMotionCoordinator(layout: layout)
        motion.update(layout: layout, state: .pinned, policy: .full)
        for _ in 0..<180 { motion.advance(by: 1.0 / 60) }
        motion.update(layout: layout, state: .compact, policy: .full)
        for _ in 0..<180 {
            motion.advance(by: 1.0 / 60)
            if motion.progress < 0.2 {
                XCTAssertEqual(motion.shoulderHeight, motion.frame.height - motion.cornerRadius, accuracy: 0.001)
            }
        }
        XCTAssertFalse(motion.isRunning)
    }

    func testStatusRevealProtectsNotchBeforeShowingGlyphs() {
        XCTAssertEqual(RailGeometry.statusOpacity(availableWing: 46, displayedGroup: 21,
                                                  requiredGroup: 74, clearance: 12), 0)
        XCTAssertEqual(RailGeometry.statusOpacity(availableWing: 98, displayedGroup: 74,
                                                  requiredGroup: 74, clearance: 12), 1)
        let middle = RailGeometry.statusOpacity(availableWing: 94, displayedGroup: 70,
                                                 requiredGroup: 74, clearance: 12)
        XCTAssertGreaterThan(middle, 0)
        XCTAssertLessThan(middle, 1)
    }

    @MainActor func testCompletionWhilePinnedDoesNotDismissTray() async {
        let model = AppModel(fixture: snapshot([("a", .thinking)]))
        model.clickIsland()
        model.setFixture(snapshot([("a", .completed)], at: now.addingTimeInterval(1)))
        try? await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(model.presentation, .pinned)
        XCTAssertEqual(model.compactLabel, "")
        XCTAssertFalse(model.rail.usesWorkingWidth)
        await model.stop()
    }

    private func layout(_ geometry: RailGeometry, _ calibration: Calibration = .init(), working: Bool = true) -> IslandLayout {
        IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                               safeTopInset: 32, leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                               calibration: calibration, railGeometry: geometry, usesWorkingWidth: working)
    }
}

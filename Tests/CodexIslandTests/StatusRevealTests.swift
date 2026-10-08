import XCTest
@testable import CodexIsland

final class StatusRevealTests: XCTestCase {
    @MainActor
    func testRevealSlidesUpWithoutRotationAndSettlesClearly() {
        let start = StatusRevealFrame(progress: 0, fontSize: 13, reduceMotion: false)
        XCTAssertEqual(start.offset, 5.2, accuracy: 0.001)
        XCTAssertEqual(start.alpha, 0)
        XCTAssertEqual(start.blurRadius, 3)
        let end = StatusRevealFrame(progress: 1, fontSize: 13, reduceMotion: false)
        XCTAssertEqual(end.offset, 0)
        XCTAssertEqual(end.alpha, 1)
        XCTAssertEqual(end.blurRadius, 0)
    }

    @MainActor
    func testReducedMotionKeepsOnlyOpacityAndClampsSpringOvershoot() {
        let middle = StatusRevealFrame(progress: 0.5, fontSize: 18, reduceMotion: true)
        XCTAssertEqual(middle.offset, 0)
        XCTAssertEqual(middle.blurRadius, 0)
        XCTAssertEqual(middle.alpha, 0.5)
        let overshoot = StatusRevealFrame(progress: 1.1, fontSize: 18, reduceMotion: false)
        XCTAssertEqual(overshoot.alpha, 1)
        XCTAssertEqual(overshoot.blurRadius, 0)
        XCTAssertEqual(overshoot.offset, 0)
    }
}

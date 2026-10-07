import XCTest
@testable import CodexIsland

final class CompactFootprintTests: XCTestCase {
    func testSavedShortShoulderCannotPinchCompactWave() {
        let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                             safeTopInset: 32, leftAuxiliaryMaxX: 660,
                                             rightAuxiliaryMinX: 852, calibration: .init(shoulderReach: 36),
                                             compactWingWidth: 76)
        XCTAssertEqual(layout.shoulderReach(at: 0), 128)
        // Quintic wave's maximum slope is 1.875 * height / reach, under 26 degrees.
        XCTAssertLessThan(1.875 * 32 / layout.shoulderReach(at: 0), 0.5)
        XCTAssertEqual(layout.shoulderReach(at: 1), 36)
    }
    func testCompactShouldersHaveGentleHorizontalTangentsAtBothEnds() {
        let path = IslandContour.path(size: CGSize(width: 500, height: 32), radius: 0,
                                      shoulderReach: 70, shoulderHeight: 32, shoulderBlend: 0)
        var curves: [[CGPoint]] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .addCurveToPoint {
                curves.append((0..<3).map { element.points[$0] })
            }
        }
        let right = curves[0], rightEnd = curves[7], left = curves[curves.count - 1]
        XCTAssertEqual(right[0].y, 0)
        XCTAssertEqual(rightEnd[1].y, 32)
        XCTAssertEqual(rightEnd[2].y, 32)
        XCTAssertEqual(right[0].x, 500 - 70 / 24, accuracy: 0.001)
        XCTAssertEqual(left[1].y, 0)
        XCTAssertEqual(left[2], .zero)
    }
    func testEachChatCubeGrowsCompactRailEvenWithLongStatus() {
        let one = CompactRailSizing.wingWidth(cubeCount: 1, statusTextWidth: 70)
        let two = CompactRailSizing.wingWidth(cubeCount: 2, statusTextWidth: 70)
        let three = CompactRailSizing.wingWidth(cubeCount: 3, statusTextWidth: 70)
        XCTAssertEqual(two - one, 28)
        XCTAssertEqual(three - two, 28)
        XCTAssertGreaterThan(CompactRailSizing.wingWidth(cubeCount: 4, statusTextWidth: 70), three)
    }

    func testCompactTaperAndContentClearanceAcrossTransition() {
        let gap: CGFloat = 192
        let wing = CompactRailSizing.wingWidth(cubeCount: 1, statusTextWidth: 35)
        let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                             safeTopInset: 32, leftAuxiliaryMaxX: 660,
                                             rightAuxiliaryMinX: 852, calibration: .init(), compactWingWidth: wing)
        XCTAssertEqual(layout.shoulderReach(at: 0), 128)
        XCTAssertEqual(layout.shoulderReach(at: 1), 100)
        XCTAssertLessThan(layout.compactFrame.width, 650)
        XCTAssertEqual(layout.withCompactWidth(layout.compactFrame.width), layout)
        for step in 0...200 {
            let p = Double(step) / 100
            XCTAssertGreaterThanOrEqual(layout.bodyWidth(at: p), gap + 2 * (wing + CompactRailSizing.railInset) - 0.01)
            XCTAssertEqual(layout.frame(at: p).midX, 756, accuracy: 0.001)
            XCTAssertEqual(layout.frame(at: p).maxY, 982, accuracy: 0.001)
        }
    }
}

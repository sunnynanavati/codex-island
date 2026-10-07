import XCTest
@testable import CodexIsland

final class ShapeSettingsTests: XCTestCase {
    func testManualAutomaticManualRoundTripPreservesWaveAndLayout() throws {
        var calibration = Calibration(waveReach: 61)
        let original = calibration
        calibration.setAutomaticWaveReach(true, automaticReach: 152)
        XCTAssertNil(calibration.waveReach)
        calibration = try JSONDecoder().decode(Calibration.self, from: JSONEncoder().encode(calibration))
        calibration.setAutomaticWaveReach(false, automaticReach: 152)
        XCTAssertEqual(calibration, original)
        XCTAssertEqual(layout(size: 0, wave: calibration.waveReach!).compactFrame,
                       layout(size: 0, wave: 61).compactFrame)
        calibration.waveReach = 83
        calibration.setAutomaticWaveReach(true, automaticReach: 152)
        calibration.setAutomaticWaveReach(true, automaticReach: 152)
        calibration.setAutomaticWaveReach(false, automaticReach: 152)
        XCTAssertEqual(calibration.waveReach, 83)
    }

    func testFirstManualToggleUsesActualAutomaticReachRatherThanHardCodedWidth() {
        var calibration = Calibration()
        calibration.setAutomaticWaveReach(false, automaticReach: 152)
        XCTAssertEqual(calibration.waveReach, 152)
        calibration.setAutomaticWaveReach(false, automaticReach: 180)
        XCTAssertEqual(calibration.waveReach, 152)
    }

    func testExistingManualCalibrationRemembersValueWhenDecoded() throws {
        var calibration = try JSONDecoder().decode(Calibration.self, from: Data("{\"waveReach\":61}".utf8))
        calibration.setAutomaticWaveReach(true, automaticReach: 152)
        calibration.setAutomaticWaveReach(false, automaticReach: 152)
        XCTAssertEqual(calibration.waveReach, 61)
    }

    private func layout(size: Double, wave: Double = 128, wing: CGFloat = 76) -> IslandLayout {
        IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                               safeTopInset: 32, leftAuxiliaryMaxX: 660, rightAuxiliaryMinX: 852,
                               calibration: .init(waveReach: wave, compactSize: size), compactWingWidth: wing)
    }
    func testSizeRangeStopsAtContentFitAndHoverWidth() {
        let smallest = layout(size: 0), largest = layout(size: 1)
        XCTAssertEqual(largest.compactFrame.width, largest.previewFrame.width)
        XCTAssertEqual(smallest.previewFrame.width, largest.previewFrame.width)
        XCTAssertEqual(layout(size: -1).compactFrame, smallest.compactFrame)
        XCTAssertEqual(layout(size: 2).compactFrame, largest.compactFrame)
        XCTAssertEqual(layout(size: 0.5).compactFrame.width,
                       (smallest.compactFrame.width + largest.compactFrame.width) / 2)
        XCTAssertEqual(smallest.bodyWidth(at: 0), 192 + 2 * (76 + CompactRailSizing.railInset))
    }
    func testSizeStillAdaptsToMoreCubesAndFontWidth() {
        for size in [0.0, 0.5, 1.0] {
            XCTAssertGreaterThan(layout(size: size, wing: 132).compactFrame.width, layout(size: size).compactFrame.width)
        }
    }
    func testExplicitWaveOverridesAutomaticMinimumWithoutRemovingContentSpace() {
        let short = layout(size: 0, wave: 40), long = layout(size: 0, wave: 220)
        XCTAssertEqual(short.compactShoulderReach, 40)
        XCTAssertEqual(long.compactShoulderReach, 220)
        XCTAssertEqual(short.bodyWidth(at: 0), long.bodyWidth(at: 0))
    }
    func testShapePreferencesPersistAndOldPreferencesMigrate() throws {
        let value = Calibration(waveReach: 160, compactSize: 0.42)
        XCTAssertEqual(try JSONDecoder().decode(Calibration.self, from: JSONEncoder().encode(value)), value)
        let old = try JSONDecoder().decode(Calibration.self, from: Data("{\"shoulderReach\":36}".utf8))
        XCTAssertNil(old.waveReach)
        XCTAssertEqual(old.compactSize, 0)
    }
}

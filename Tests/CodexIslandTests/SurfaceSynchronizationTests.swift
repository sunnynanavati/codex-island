import AppKit
import XCTest
@testable import CodexIsland

final class SurfaceSynchronizationTests: XCTestCase {
    func testPixelAlignmentPreservesTopEdgeAcrossAllSizes() {
        for scale: CGFloat in [1, 2, 3] {
            for height: CGFloat in stride(from: 38, through: 480, by: 0.37) {
                let frame = CGRect(x: 427.13, y: 982 - height, width: 657.71, height: height)
                let aligned = IslandPanelGeometry.alignedFrame(frame, scale: scale)
                XCTAssertEqual(aligned.maxY, 982)
                for edge in [aligned.minX, aligned.maxX, aligned.minY, aligned.maxY] {
                    XCTAssertEqual(edge * scale, (edge * scale).rounded(), accuracy: 0.000001)
                }
                XCTAssertEqual(aligned.midX, frame.midX, accuracy: 0.5 / scale)
            }
        }
    }

    @MainActor func testNativeSurfaceFillsTopAndUsesCurrentBoundsDuringReversals() {
        let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                            safeTopInset: 38, leftAuxiliaryMaxX: 660,
                                            rightAuxiliaryMinX: 852, calibration: .init())
        let motion = IslandMotionCoordinator(layout: layout)
        let surface = IslandSurfaceView(frame: .zero)
        for state: PresentationState in [.preview, .compact, .pinned, .preview, .compact] {
            motion.update(layout: layout, state: state, policy: .full)
            for _ in 0..<9 {
                motion.advance(by: 1 / 60)
                let frame = IslandPanelGeometry.alignedFrame(motion.frame, scale: 2)
                surface.frame = CGRect(origin: .zero, size: frame.size)
                surface.updateContour(radius: motion.cornerRadius,
                                      shoulderReach: layout.shoulderReach(at: motion.progress),
                                      shoulderHeight: motion.shoulderHeight, blend: min(1, max(0, motion.progress)))
                XCTAssertEqual(surface.layer?.mask?.frame.size, frame.size)
                XCTAssertNotNil(surface.layer?.backgroundColor)
                XCTAssertTrue(surface.contour.contains(CGPoint(x: frame.width / 2, y: 0.25)))
                XCTAssertFalse(surface.contour.contains(CGPoint(x: 0.25, y: frame.height - 0.25)))
                XCTAssertEqual(frame.maxY, layout.compactFrame.maxY)
            }
        }
        for _ in 0..<180 { motion.advance(by: 1 / 60) }
        XCTAssertFalse(motion.isRunning)
    }
}

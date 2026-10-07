import AppKit
import QuartzCore

enum IslandPanelGeometry {
    static func alignedFrame(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let left = (frame.minX * scale).rounded() / scale
        let right = (frame.maxX * scale).rounded() / scale
        let top = (frame.maxY * scale).rounded() / scale
        let height = (frame.height * scale).rounded() / scale
        return CGRect(x: left, y: top - height, width: right - left, height: height)
    }
}

/// The window surface must not wait for SwiftUI to redraw after a native resize.
@MainActor final class IslandSurfaceView: NSView {
    private let surfaceMask = CAShapeLayer()
    private(set) var contour = CGPath(rect: .zero, transform: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        surfaceMask.fillColor = NSColor.white.cgColor
        layer?.mask = surfaceMask
    }

    required init?(coder: NSCoder) { nil }

    func updateContour(radius: CGFloat, shoulderReach: CGFloat, shoulderHeight: CGFloat, blend: CGFloat) {
        contour = IslandContour.path(size: bounds.size, radius: radius,
                                     shoulderReach: shoulderReach, shoulderHeight: shoulderHeight,
                                     shoulderBlend: blend)
        var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        surfaceMask.frame = bounds
        surfaceMask.path = layer?.isGeometryFlipped == true ? contour : contour.copy(using: &flip)
    }
}

import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 204, yRadius: 204).fill()
        let colors: [NSColor] = [.systemGreen, .systemGreen, .systemTeal,
                                 .systemGreen, .systemTeal, .systemBlue,
                                 .systemGreen, .systemGreen, .systemGreen]
        for row in 0..<3 {
            for column in 0..<3 {
                colors[row * 3 + column].setFill()
                NSBezierPath(roundedRect: NSRect(x: 273 + column * 166, y: 273 + row * 166,
                    width: 146, height: 146), xRadius: 26, yRadius: 26).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to:
            destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

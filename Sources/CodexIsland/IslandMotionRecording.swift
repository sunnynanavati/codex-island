import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Captures only the app's synthetic panel surface, never the desktop or chats.
@MainActor
enum IslandMotionRecording {
    static func record(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let preferences = PreferencesStore(defaults: nil)
        let model = AppModel(fixture: IslandFixtures.snapshot("idle"), preferences: preferences)
        let controller = PanelController(model: model, cubeFrozenOverride: false)
        defer { controller.shutdown() }
        let destinations = try [("motion-normal.gif", 1.0), ("motion-slow.gif", 3.0)].map { name, speed in
            guard let destination = CGImageDestinationCreateWithURL(directory.appendingPathComponent(name) as CFURL,
                                                                    UTType.gif.identifier as CFString, 0, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            return (destination, speed)
        }
        let steps: [(Double, () -> Void)] = [
            (0.4, { model.setFixture(IslandFixtures.snapshot("active")) }),
            (1.1, { model.setFixture(IslandFixtures.snapshot("multiple")) }),
            (1.8, { model.setFixture(IslandFixtures.snapshot("mixed")) }),
            (2.4, { model.setFixture(IslandFixtures.snapshot("completed")) }),
            (2.65, { model.setFixture(IslandFixtures.snapshot("active")) }),
            (3.2, { model.hover(true) }),
            (3.38, { model.hover(false) }),
            (3.48, { model.hover(true) }),
            (3.65, { model.clickIsland() }),
            (3.95, {
                var snapshot = IslandFixtures.snapshot("active")
                snapshot.tasks[0].updatedAt = Date().addingTimeInterval(-125)
                model.setFixture(snapshot)
            }),
            (4.12, {
                var snapshot = IslandFixtures.snapshot("active")
                snapshot.tasks[0].updatedAt = Date().addingTimeInterval(-185)
                model.setFixture(snapshot)
            }),
            (4.3, { model.setFixture(IslandFixtures.snapshot("completed")) }),
            (5.0, { model.dismiss() }),
            (5.7, { model.setFixture(IslandFixtures.snapshot("active")); model.typography.statusSize = 14 }),
            (6.4, { model.setFixture(IslandFixtures.snapshot("completed")) })
        ]
        let start = Date()
        var previous = start
        var index = 0
        var frames = 0
        while Date().timeIntervalSince(start) < 7.7 {
            let now = Date()
            while index < steps.count, now.timeIntervalSince(start) >= steps[index].0 {
                steps[index].1(); index += 1
            }
            if let (surface, size) = controller.captureSurface(),
               let context = CGContext(data: nil, width: 1000, height: 520, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.setFillColor(CGColor(red: 0.32, green: 0.51, blue: 0.62, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 1000, height: 520))
                let scale = min(1, 1000 / size.width)
                let width = size.width * scale, height = size.height * scale
                context.draw(surface, in: CGRect(x: (1000 - width) / 2, y: 520 - height, width: width, height: height))
                if let frame = context.makeImage() {
                    let delay = max(0.02, now.timeIntervalSince(previous))
                    for (destination, speed) in destinations {
                        CGImageDestinationAddImage(destination, frame,
                                                   [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay * speed]] as CFDictionary)
                    }
                    frames += 1
                }
            }
            previous = now
            try await Task.sleep(for: .milliseconds(40))
        }
        for (destination, _) in destinations {
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        }
        await model.stop()
        AppLog.write("Recorded \(frames) native synthetic panel samples; playback timing reflects capture intervals, not a frame-rate benchmark")
    }
}

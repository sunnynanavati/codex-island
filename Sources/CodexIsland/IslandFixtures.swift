import AppKit
import SwiftUI

enum IslandFixtures {
    static let names = ["idle", "active", "multiple", "mixed", "attention", "question", "completed", "failed", "cancelled", "critical-quota", "unavailable", "error"]

    static func snapshot(_ name: String, now: Date = Date()) -> IslandSnapshot {
        func task(_ id: String, _ title: String, _ state: ActivityState) -> TaskSnapshot {
            TaskSnapshot(id: id, title: title, workspacePath: "/tmp/Orchard", rolloutPath: nil,
                         state: state, updatedAt: now, startedAt: now.addingTimeInterval(-120),
                         completedTurns: [], activityIntervals: [], pendingQuestion: nil, quota: nil,
                         isChildAgent: false, agentCount: 1, error: nil)
        }
        var tasks = [task("primary", "Refine the details. Make every interaction feel natural.", .thinking)]
        if name == "idle" { tasks = [] }
        if name == "long-title" {
            tasks[0].title = "Refine the native island experience with stable chat companions, precise typography, graceful transitions, and recoverable local task details without losing any part of a long task title."
        }
        if name == "multiple" {
            tasks += [task("two", "Build the native settings experience", .editing),
                      task("three", "Check keyboard and VoiceOver navigation", .reading),
                      task("four", "Run the regression suite", .running),
                      task("five", "Review the release notes", .planning)]
        }
        if name == "attention" || name == "question" {
            tasks[0].state = .waitingForInput
            tasks[0].pendingQuestion = PendingQuestion(
                id: "appearance", header: "A small design decision", prompt: "Which appearance should this workspace use?",
                choices: [.init(label: "Follow the system", description: "Match the appearance selected in macOS."),
                          .init(label: "Always dark", description: "Keep a quiet, dark workspace throughout the day.")])
        }
        if name == "completed" { tasks[0].state = .completed }
        if name == "mixed" {
            tasks[0].state = .completed
            tasks.append(task("two", "Build the native settings experience", .editing))
        }
        if name == "failed" { tasks[0].state = .failed }
        if name == "cancelled" { tasks[0].state = .cancelled }
        tasks.append(task("recent", "Polish the command palette", .completed))
        tasks[tasks.count - 1].updatedAt = now.addingTimeInterval(-600)
        return IslandSnapshot(tasks: tasks, primaryTaskID: name == "idle" ? nil : "primary",
                              dailyStats: .init(completedTurns: 24, activeDuration: 4980),
                              quota: name == "unavailable" ? nil : .init(usedPercent: name == "critical-quota" ? 80 : 26,
                                                                          windowMinutes: 10080, resetAt: now.addingTimeInterval(86400)),
                              refreshedAt: now,
                              errorMessage: name == "error" ? "Codex data is temporarily unavailable. Showing the last successful update. Refresh to retry; if this persists, reopen Codex and refresh again." : nil)
    }
}

@MainActor
enum IslandPreviewRenderer {
    static func render(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var specifications = IslandFixtures.names.map { ($0, $0, PresentationState.pinned, IslandPage.activity) }
        specifications += [("compact", "multiple", .compact, .activity),
                           ("compact-idle", "idle", .compact, .activity),
                           ("compact-calibrated-adaptive", "idle", .compact, .activity),
                           ("compact-calibrated-manual", "idle", .compact, .activity),
                           ("compact-critical", "critical-quota", .compact, .activity),
                           ("compact-unavailable", "unavailable", .compact, .activity),
                           ("preview", "active", .preview, .activity),
                           ("preview-idle", "idle", .preview, .activity),
                           ("recent", "active", .pinned, .recent),
                           ("task-details", "long-title", .pinned, .task("primary")),
                           ("reduced-motion", "active", .pinned, .activity), ("high-contrast", "active", .pinned, .activity)]
        var images: [(String, NSImage)] = []
        for (filename, scenario, stage, page) in specifications {
            let model = AppModel(fixture: IslandFixtures.snapshot(scenario))
            if scenario == "completed" || scenario == "mixed" {
                model.setFixture(IslandFixtures.snapshot(scenario == "mixed" ? "multiple" : "active"))
                model.setFixture(IslandFixtures.snapshot(scenario))
            }
            let calibration = filename.hasPrefix("compact-calibrated-")
                ? Calibration(widthAdjustment: 120, shoulderReach: 36,
                              adaptiveWidth: filename == "compact-calibrated-adaptive")
                : Calibration()
            model.calibration = calibration
            model.glyphTheme = .cube
            model.presentation = stage
            model.page = scenario == "question" ? .question("primary") : page
            let layout = IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                               safeTopInset: 38, leftAuxiliaryMaxX: 660,
                                               rightAuxiliaryMinX: 852, calibration: calibration,
                                               railGeometry: PanelController.railGeometry(
                                                cubeCount: model.cubes.count, label: model.rail.sizingLabel,
                                                typography: model.typography, preferences: model.preferences.values, displayScale: 2),
                                               usesWorkingWidth: model.rail.usesWorkingWidth)
            let motion = IslandMotionCoordinator(layout: layout)
            model.notchGap = layout.notchGapWidth
            motion.update(layout: layout, state: stage, policy: .immediate)
            let root = IslandView(model: model, motion: motion,
                                  reduceMotionOverride: filename == "reduced-motion",
                                  increasedContrastOverride: filename == "high-contrast")
            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = []
            let bounds = CGRect(origin: .zero, size: motion.frame.size)
            let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.contentView = hosting
            hosting.frame = bounds
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(280))
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            hosting.cacheDisplay(in: bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
            try data.write(to: directory.appendingPathComponent(filename + ".png"))
            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmap)
            if filename == "compact-idle" {
                // An opaque backdrop makes the transparent contour reviewable on dark viewers.
                let contourReview = NSImage(size: bounds.size)
                contourReview.lockFocus()
                NSColor(calibratedRed: 0.36, green: 0.66, blue: 0.86, alpha: 1).setFill()
                bounds.fill()
                image.draw(in: bounds)
                contourReview.unlockFocus()
                if let tiff = contourReview.tiffRepresentation,
                   let reviewBitmap = NSBitmapImageRep(data: tiff),
                   let png = reviewBitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: directory.appendingPathComponent("compact-contour-review.png"))
                }
            }
            images.append((filename, image))
            window.close()
        }
        let cell = CGSize(width: 330, height: 380)
        let rows = Int(ceil(Double(images.count) / 3))
        let sheet = NSImage(size: CGSize(width: cell.width * 3, height: cell.height * CGFloat(rows)))
        sheet.lockFocus()
        NSColor(white: 0.16, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        for (index, entry) in images.enumerated() {
            let x = CGFloat(index % 3) * cell.width + 14
            let y = sheet.size.height - CGFloat(index / 3 + 1) * cell.height
            (entry.0 as NSString).draw(at: CGPoint(x: x, y: y + cell.height - 26),
                                      withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
            let scale = min(1, (cell.width - 28) / entry.1.size.width)
            let size = CGSize(width: entry.1.size.width * scale, height: entry.1.size.height * scale)
            entry.1.draw(in: CGRect(x: x, y: y + cell.height - 38 - size.height, width: size.width, height: size.height))
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("contact-sheet.png"))
        }
        try renderStatusFlipFrames(to: directory)
        AppLog.write("Rendered \(images.count) synthetic states")
    }

    private static func renderStatusFlipFrames(to directory: URL) throws {
        let phases: [Double] = [0, 0.15, 0.25, 0.35, 0.5, 0.65, 0.75, 0.85, 1]
        let cell = CGSize(width: 230, height: 80)
        let sheet = NSImage(size: CGSize(width: cell.width * 3, height: cell.height * 3))
        sheet.lockFocus()
        NSColor(white: 0.14, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        for (index, phase) in phases.enumerated() {
            let specimen = ZStack {
                Text("Thinking")
                    .modifier(StatusFlipFrame(progress: phase, entering: false, reduceMotion: false))
                Text("Running")
                    .modifier(StatusFlipFrame(progress: phase, entering: true, reduceMotion: false))
            }
            .font(IslandFont.regular(size: 12))
            .foregroundStyle(.white)
            .frame(width: 190, height: 32)
            .background(.black)
            let renderer = ImageRenderer(content: specimen)
            renderer.scale = 2
            if let image = renderer.nsImage {
                let x = CGFloat(index % 3) * cell.width + 20
                let y = sheet.size.height - CGFloat(index / 3 + 1) * cell.height + 12
                image.draw(in: CGRect(x: x, y: y, width: 190, height: 32))
                ("\(Int(phase * 100))%" as NSString).draw(
                    at: CGPoint(x: x, y: y + 43),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white]
                )
            }
        }
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: directory.appendingPathComponent("status-flip-frames.png"))
        }
    }
}

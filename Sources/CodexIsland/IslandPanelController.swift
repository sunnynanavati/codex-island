import AppKit
import SwiftUI

@MainActor
final class IslandPanel: NSPanel {
    var permitsKeyboard = false
    override var canBecomeKey: Bool { permitsKeyboard }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    private let panel: IslandPanel
    private let surfaceMask = CAShapeLayer()
    private let model: AppModel
    private let motion: IslandMotionCoordinator
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var previousState = PresentationState.compact
    private var previousApplication: NSRunningApplication?

    init(model: AppModel, cubeFrozenOverride: Bool? = nil) {
        self.model = model
        let layout = Self.layout(calibration: model.calibration, cubeCount: model.cubes.count,
                                 statusLabel: model.compactLabel, typography: model.typography,
                                 preferences: model.preferences.values, sizingLabel: model.rail.sizingLabel,
                                 usesWorkingWidth: model.rail.usesWorkingWidth)
        motion = IslandMotionCoordinator(layout: layout)
        panel = IslandPanel(contentRect: layout.compactFrame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        model.notchGap = layout.notchGapWidth
        let hosting = NSHostingView(rootView: IslandView(model: model, motion: motion, cubeFrozenOverride: cubeFrozenOverride))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        panel.contentView = hosting
        surfaceMask.fillColor = NSColor.white.cgColor
        hosting.layer?.mask = surfaceMask
        motion.attach(to: hosting)
        motion.onFrame = { [weak self] frame in
            guard let self else { return }
            self.updateSurfaceMask(size: frame.size)
            self.panel.setFrame(frame, display: true)
            self.updateClickThrough()
        }
        model.onLayoutChange = { [weak self] in self?.updateLayout() }
        observe(.default, NSApplication.didChangeScreenParametersNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        installEventMonitors()
        updateLayout()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLayout() }
        }
        observers.append((center, token))
    }

    private func installEventMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointer(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53, self.panel.isKeyWindow, self.model.presentation == .pinned {
                AppLog.write("Island dismissed with Escape")
                self.model.dismiss()
                return nil
            }
            self.handlePointer(event)
            return event
        }
    }

    private var pointerInside: Bool {
        let point = NSEvent.mouseLocation
        return IslandHitRegion.contains(CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY),
                                        size: panel.frame.size, radius: motion.cornerRadius,
                                        shoulderReach: motion.layout.shoulderReach(at: motion.progress),
                                        shoulderHeight: motion.shoulderHeight,
                                        shoulderBlend: min(1, max(0, motion.progress)))
    }

    private func handlePointer(_ event: NSEvent) {
        guard model.preferences.values.showIsland, panel.isVisible else { return }
        if event.type == .mouseMoved {
            // Only actual pointer motion changes hover intent; resizing beneath it does not.
            updateClickThrough()
            model.hover(pointerInside)
        } else if [.leftMouseDown, .rightMouseDown].contains(event.type),
                  model.presentation == .pinned, !pointerInside {
            AppLog.write("Island dismissed by an outside click")
            previousApplication = nil
            model.dismiss()
        }
    }

    private func updateClickThrough() {
        panel.ignoresMouseEvents = panel.frame.contains(NSEvent.mouseLocation) && !pointerInside
    }

    private func updateSurfaceMask(size: CGSize) {
        let contour = IslandContour.path(size: size, radius: motion.cornerRadius,
                                         shoulderReach: motion.layout.shoulderReach(at: motion.progress),
                                         shoulderHeight: motion.shoulderHeight,
                                         shoulderBlend: min(1, max(0, motion.progress)))
        var flip = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
        let path = panel.contentView?.layer?.isGeometryFlipped == true ? contour : contour.copy(using: &flip)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceMask.frame = CGRect(origin: .zero, size: size)
        surfaceMask.path = path
        CATransaction.commit()
    }

    func updateLayout() {
        guard model.preferences.values.showIsland else {
            motion.stop()
            panel.orderOut(nil)
            previousState = .compact
            return
        }
        let layout = Self.layout(calibration: model.calibration, cubeCount: model.cubes.count,
                                 statusLabel: model.compactLabel, typography: model.typography,
                                 preferences: model.preferences.values, sizingLabel: model.rail.sizingLabel,
                                 usesWorkingWidth: model.rail.usesWorkingWidth)
        model.notchGap = layout.notchGapWidth
        motion.speed = model.preferences.values.springSpeed
        panel.permitsKeyboard = model.presentation == .pinned
        motion.update(layout: layout, state: model.presentation,
                      policy: .resolve(enabled: model.animationsEnabled,
                                       reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
        if model.presentation == .pinned, previousState != .pinned {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication = front
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else if model.presentation != .pinned, panel.isKeyWindow {
            panel.resignKey()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                previousApplication?.activate(options: [])
            }
            previousApplication = nil
        }
        previousState = model.presentation
        panel.orderFrontRegardless()
    }

    static func layout(calibration: Calibration, cubeCount: Int, statusLabel: String,
                       typography: CompactTypography = .init(),
                       preferences: IslandPreferences? = nil, sizingLabel: String? = nil,
                       usesWorkingWidth: Bool = true) -> IslandLayout {
        let screens = NSScreen.screens
        let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first
        let geometry = railGeometry(cubeCount: cubeCount, label: sizingLabel ?? (statusLabel.isEmpty ? nil : statusLabel),
                                    typography: typography, preferences: preferences,
                                    displayScale: screen?.backingScaleFactor ?? 2)
        guard let screen else {
            return IslandLayout.calculate(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                          safeTopInset: 32, leftAuxiliaryMaxX: nil,
                                          rightAuxiliaryMinX: nil, calibration: calibration,
                                          railGeometry: geometry, usesWorkingWidth: usesWorkingWidth)
        }
        return IslandLayout.calculate(screenFrame: screen.frame, safeTopInset: screen.safeAreaInsets.top,
                                      leftAuxiliaryMaxX: screen.auxiliaryTopLeftArea?.maxX,
                                      rightAuxiliaryMinX: screen.auxiliaryTopRightArea?.minX,
                                      calibration: calibration, railGeometry: geometry, usesWorkingWidth: usesWorkingWidth)
    }

    static func railGeometry(cubeCount: Int, label: String?, typography: CompactTypography,
                             preferences: IslandPreferences? = nil, displayScale: CGFloat) -> RailGeometry {
        let font = IslandFont.nsFont(weight: typography.statusWeight, size: CGFloat(typography.statusSize),
                                     family: preferences?.fontFamily ?? .nunito)
        let textWidth = label.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 2 } ?? 0
        let ringWidth = CompactQuotaRing.diameter + (preferences?.ringStroke ?? 1.2)
        return RailGeometry(cubeWidth: RailGeometry.cubeWidth(count: cubeCount),
                            statusWidth: ringWidth + (label == nil ? 0 : textWidth + (preferences?.statusGap ?? 9)),
                            clearance: RailGeometry.clearance(displayScale: displayScale))
    }

    static func compactWingWidth(cubeCount: Int, statusLabel: String,
                                 typography: CompactTypography = .init(),
                                 preferences: IslandPreferences? = nil) -> CGFloat {
        let font = IslandFont.nsFont(weight: typography.statusWeight, size: CGFloat(typography.statusSize),
                                     family: preferences?.fontFamily ?? .nunito)
        let textWidth = (statusLabel as NSString).size(withAttributes: [.font: font]).width
        return CompactRailSizing.wingWidth(cubeCount: cubeCount, statusTextWidth: textWidth)
            + CGFloat((preferences?.statusGap ?? 9) - 9)
    }

    func shutdown() {
        model.onLayoutChange = nil
        motion.stop()
        motion.onFrame = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    func captureSurface() -> (CGImage, CGSize)? {
        guard let view = panel.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return nil }
        return (image, bounds.size)
    }
}

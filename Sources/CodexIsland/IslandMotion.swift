import AppKit
import Combine
import QuartzCore

enum IslandMotionPolicy {
    case full, reduced, immediate

    static func resolve(enabled: Bool, reduceMotion: Bool) -> Self {
        !enabled ? .immediate : reduceMotion ? .reduced : .full
    }
}

enum IslandContentReveal {
    private static func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }

    static func previewOpacity(_ progress: Double, eligible: Bool) -> Double {
        guard eligible else { return 0 }
        if progress <= 1 { return clamp01((progress - 0.12) / 0.78) }
        return 1 - clamp01((progress - 1.10) / 0.35)
    }

    static func expandedOpacity(_ progress: Double, previewEligible: Bool) -> Double {
        if previewEligible { return clamp01((progress - 1.32) / 0.48) }
        return clamp01((progress - 0.90) / 0.75)
    }

    static func previewYOffset(_ progress: Double, opacity: Double,
                               movementAllowed: Bool) -> CGFloat {
        guard movementAllowed else { return 0 }
        return CGFloat((progress <= 1 ? 6 : -4) * (1 - opacity))
    }

    static func expandedYOffset(opacity: Double, movementAllowed: Bool) -> CGFloat {
        guard movementAllowed else { return 0 }
        return CGFloat(6 * (1 - opacity))
    }
}

@MainActor
final class IslandMotionCoordinator: NSObject, ObservableObject {
    @Published private(set) var progress = 0.0
    @Published private(set) var contentOpacity = 1.0
    @Published private(set) var previewContentEligible = false
    @Published private(set) var layout: IslandLayout
    private(set) var spring = IslandSpring()
    private(set) var widthSpring: IslandSpring
    private(set) var statusWidthSpring: IslandSpring
    private var previewWidthSpring: IslandSpring
    private var expandedWidthSpring: IslandSpring
    private(set) var expandedHeightSpring: IslandSpring
    private var targetLayout: IslandLayout
    private var displayLink: CADisplayLink?
    private weak var displayView: NSView?
    private var lastTime = 0.0
    private var fadeStarted = 0.0
    private var policy = IslandMotionPolicy.full
    var onFrame: ((CGRect) -> Void)?
    var speed = 1.0
    var isRunning: Bool { displayLink != nil }
    var frame: CGRect { layout.frame(at: progress) }
    var cornerRadius: CGFloat { 26 * min(1, max(0, progress)) }
    var shoulderHeight: CGFloat {
        let t = min(1, max(0, (progress - 0.2) / 0.6))
        let blend = t * t * (3 - 2 * t)
        let fullDepth = max(layout.compactFrame.height, frame.height - cornerRadius)
        return fullDepth + (layout.compactFrame.height - fullDepth) * blend
    }

    init(layout: IslandLayout) {
        self.layout = layout
        targetLayout = layout
        widthSpring = IslandSpring(value: layout.compactFrame.width, velocity: 0,
                                   target: layout.compactFrame.width)
        statusWidthSpring = IslandSpring(value: Double(layout.railGeometry?.statusWidth ?? 0), velocity: 0,
                                        target: Double(layout.railGeometry?.statusWidth ?? 0))
        previewWidthSpring = IslandSpring(value: layout.previewFrame.width, velocity: 0, target: layout.previewFrame.width)
        expandedWidthSpring = IslandSpring(value: layout.expandedFrame.width, velocity: 0, target: layout.expandedFrame.width)
        expandedHeightSpring = IslandSpring(value: layout.expandedFrame.height, velocity: 0, target: layout.expandedFrame.height)
        super.init()
    }

    func attach(to view: NSView) { displayView = view }

    func update(layout: IslandLayout, state: PresentationState, policy: IslandMotionPolicy) {
        let geometryChanged = widthSpring.target != layout.compactFrame.width ||
            statusWidthSpring.target != Double(layout.railGeometry?.statusWidth ?? 0) ||
            expandedHeightSpring.target != layout.expandedFrame.height
        targetLayout = layout
        widthSpring.target = layout.compactFrame.width
        statusWidthSpring.target = Double(layout.railGeometry?.statusWidth ?? 0)
        previewWidthSpring.target = layout.previewFrame.width
        expandedWidthSpring.target = layout.expandedFrame.width
        expandedHeightSpring.target = layout.expandedFrame.height
        self.layout = sampledLayout()
        self.policy = policy
        let target = state == .compact ? 0.0 : state == .preview ? 1.0 : 2.0
        let oldTarget = spring.target
        let oldValue = spring.value
        let changed = oldTarget != target
        if changed {
            if target == 1 { previewContentEligible = true }
            else if target == 2 { previewContentEligible = oldTarget == 1 && oldValue > 0.12 }
            else { previewContentEligible = oldTarget == 1 }
        }
        spring.target = target
        if policy != .full {
            stop()
            spring.value = target
            spring.velocity = 0
            widthSpring.value = widthSpring.target
            widthSpring.velocity = 0
            statusWidthSpring.value = statusWidthSpring.target; statusWidthSpring.velocity = 0
            previewWidthSpring.value = previewWidthSpring.target; previewWidthSpring.velocity = 0
            expandedWidthSpring.value = expandedWidthSpring.target; expandedWidthSpring.velocity = 0
            expandedHeightSpring.value = expandedHeightSpring.target; expandedHeightSpring.velocity = 0
            self.layout = layout
            progress = target
            if target == 0 { previewContentEligible = false }
            onFrame?(frame)
            contentOpacity = policy == .reduced && (changed || geometryChanged) ? 0 : 1
            if contentOpacity == 0 { fadeStarted = CACurrentMediaTime(); start() }
        } else {
            contentOpacity = 1
            onFrame?(frame)
            if !settled { start() }
        }
    }

    private func start() {
        guard displayLink == nil, let displayView else { return }
        lastTime = CACurrentMediaTime()
        let link = displayView.displayLink(target: self, selector: #selector(displayTick(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func displayTick(_ link: CADisplayLink) {
        tick(at: link.targetTimestamp)
    }

    private func tick(at now: CFTimeInterval) {
        if policy == .reduced {
            contentOpacity = min(1, (now - fadeStarted) / 0.14)
            if contentOpacity >= 1 { stop() }
            return
        }
        advance(by: min(0.05, now - lastTime))
        lastTime = now
    }

    func advance(by dt: Double) {
        spring.advance(by: dt * min(1.2, max(0.8, speed)))
        widthSpring.advance(by: dt * min(1.2, max(0.8, speed)))
        statusWidthSpring.advance(by: dt * min(1.2, max(0.8, speed)))
        previewWidthSpring.advance(by: dt * min(1.2, max(0.8, speed)))
        expandedWidthSpring.advance(by: dt * min(1.2, max(0.8, speed)))
        expandedHeightSpring.advance(by: dt * min(1.2, max(0.8, speed)))
        layout = sampledLayout()
        progress = spring.value
        onFrame?(frame)
        if settled {
            if spring.target == 0 { previewContentEligible = false }
            stop()
        }
    }

    private var settled: Bool {
        spring.isSettled && widthSpring.isSettled && statusWidthSpring.isSettled &&
            previewWidthSpring.isSettled && expandedWidthSpring.isSettled && expandedHeightSpring.isSettled
    }

    private func sampledLayout() -> IslandLayout {
        let sampled = targetLayout.withCompactWidth(CGFloat(widthSpring.value))
        guard let geometry = sampled.railGeometry else { return sampled }
        func centered(_ frame: CGRect, width: Double, height: CGFloat? = nil) -> CGRect {
            let width = min(CGFloat(width), sampled.screenMaxX - sampled.screenMinX)
            let x = min(max(frame.midX - width / 2, sampled.screenMinX), sampled.screenMaxX - width)
            let height = height ?? frame.height
            return CGRect(x: x, y: frame.maxY - height, width: width, height: height)
        }
        return IslandLayout(compactFrame: sampled.compactFrame,
                            previewFrame: centered(targetLayout.previewFrame, width: previewWidthSpring.value),
                            expandedFrame: centered(targetLayout.expandedFrame, width: expandedWidthSpring.value,
                                                    height: CGFloat(expandedHeightSpring.value)),
                            notchGapWidth: sampled.notchGapWidth, shoulderReach: sampled.shoulderReach,
                            compactShoulderReach: sampled.compactShoulderReach, screenMinX: sampled.screenMinX,
                            screenMaxX: sampled.screenMaxX,
                            railGeometry: RailGeometry(cubeWidth: geometry.cubeWidth,
                                                       statusWidth: CGFloat(statusWidthSpring.value), clearance: geometry.clearance))
    }

    func stop() { displayLink?.invalidate(); displayLink = nil }
}

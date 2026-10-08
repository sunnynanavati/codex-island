import AppKit
import SwiftUI

struct CubeDescriptor: Identifiable, Equatable {
    let id: String
    var title: String
    var state: ActivityState
    var epoch: Date
    let seed: Int
    var solvedColor: Int?
    static let idle = Self(id: "idle", title: "Codex idle", state: .idle,
                           epoch: .distantPast, seed: 0, solvedColor: 0)
}

struct CubeRoster: Equatable {
    private var ordered: [CubeDescriptor] = []
    private var nextSeed = 0
    private var settled: CubeDescriptor?

    mutating func reconcile(tasks: [TaskSnapshot], now: Date, retainCompleted: Bool = false) -> [CubeDescriptor] {
        let hasLive = tasks.contains { $0.state.isActive || $0.state.needsAttention } ||
            ordered.contains { $0.state.isActive || $0.state.needsAttention ||
                ($0.state == .completed && now.timeIntervalSince($0.epoch) < CubeTimeline.completionDuration) }
        let groups = Dictionary(grouping: tasks.compactMap { task -> (String, TaskSnapshot)? in
            if task.isChildAgent {
                guard let root = task.rootChatID, root != task.id else { return nil }
                return (root, task)
            }
            return (task.id, task)
        }, by: { $0.0 })
        let eligible: [(id: String, title: String, state: ActivityState, updatedAt: Date, order: Date)] = groups.compactMap { id, entries in
            let members = entries.map(\.1)
            let root = members.first { !$0.isChildAgent && $0.id == id }
            let live = members.filter { $0.state.isActive || $0.state.needsAttention }
            let chosen: TaskSnapshot
            if let attention = live.filter({ $0.state.needsAttention }).max(by: { $0.updatedAt < $1.updatedAt }) {
                chosen = attention
            } else if let root, root.state.isActive {
                chosen = root
            } else if let active = live.max(by: { $0.updatedAt < $1.updatedAt }) {
                chosen = active
            } else if let root, root.state == .completed,
                      (ordered.contains(where: { $0.id == id && $0.state.isActive }) ||
                       (retainCompleted && hasLive && ordered.contains(where: { $0.id == id && $0.state == .completed })) ||
                       ordered.contains(where: { $0.id == id && $0.state == .completed && now.timeIntervalSince($0.epoch) < CubeTimeline.completionDuration }) ||
                       (!retainCompleted && (0..<3).contains(now.timeIntervalSince(root.updatedAt)))) {
                chosen = root
            } else { return nil }
            let order = root?.startedAt ?? root?.updatedAt ??
                members.map { $0.startedAt ?? $0.updatedAt }.min() ?? chosen.updatedAt
            return (id, root?.cleanedTitle ?? chosen.cleanedTitle, chosen.state, chosen.updatedAt, order)
        }.sorted {
            $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }
        if eligible.contains(where: { $0.state.isActive }) { settled = nil }
        let ids = Set(eligible.map(\.id))
        ordered.removeAll { !ids.contains($0.id) }
        for chat in eligible {
            if let index = ordered.firstIndex(where: { $0.id == chat.id }) {
                let old = ordered[index].state
                if old != chat.state && (!old.isActive || !chat.state.isActive || old.needsAttention != chat.state.needsAttention) {
                    ordered[index].epoch = now
                }
                ordered[index].state = chat.state
                if chat.state != .completed { ordered[index].solvedColor = nil }
                ordered[index].title = chat.title
            } else {
                ordered.append(.init(id: chat.id, title: chat.title, state: chat.state,
                                     epoch: chat.state == .completed ? chat.updatedAt : now,
                                     seed: nextSeed, solvedColor: nil))
                nextSeed += 1
            }
        }
        var solvedIndex = 0
        for index in ordered.indices where ordered[index].state == .completed {
            ordered[index].solvedColor = solvedIndex % 6
            if solvedIndex == 0 {
                var solved = ordered[index]
                solved.state = .idle
                settled = solved
            }
            solvedIndex += 1
        }
        if ordered.isEmpty {
            var idle = settled ?? .idle
            idle.solvedColor = 0
            return [idle]
        }
        return ordered
    }
}

enum CubeTimeline {
    static let completionDuration = 0.49
    static let completionOrder = [6, 7, 8, 3, 4, 5, 0, 1, 2]

    static func completion(index: Int, elapsed: Double) -> Double {
        let rank = completionOrder.firstIndex(of: index) ?? 0
        return min(1, max(0, (elapsed - Double(rank) * 0.05) / 0.09))
    }

    static func order(seed: Int, cycle: Int) -> [Int] {
        var result = Array(0..<9)
        var value = UInt64(seed) &+ UInt64(max(0, cycle)) &* 0x9E3779B97F4A7C15
        for i in stride(from: 8, through: 1, by: -1) {
            value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            result.swapAt(i, Int(value % UInt64(i + 1)))
        }
        return result
    }

    // A semantic activity indicator, not a measurement of model effort or CPU use.
    static func litCellCount(for state: ActivityState) -> Int {
        switch state {
        case .starting, .reading, .writing: 1
        case .planning, .thinking: 2
        case .scanning, .searching, .editing, .running: 3
        case .waitingForInput, .attentionRequired, .completed, .failed, .cancelled, .idle: 0
        }
    }

    static func solvingPulse(index: Int, elapsed: Double, seed: Int, state: ActivityState) -> Double {
        let count = litCellCount(for: state)
        guard count > 0, (0..<9).contains(index), elapsed.isFinite else { return 0 }
        // Each hop finishes its pulse before the next begins: never more than
        // the state's cell budget. All lanes share one clock and permutation.
        let hopDuration = 0.22
        let time = max(0, elapsed)
        let step = Int(time / hopDuration)
        let path = order(seed: seed, cycle: step / 9)
        let selected = (0..<count).contains { lane in
            path[(step % 9 + lane * (9 / count)) % 9] == index
        }
        guard selected else { return 0 }
        let local = time.truncatingRemainder(dividingBy: hopDuration)
        let pulse: Double
        if local < 0.035 { pulse = 1 - pow(1 - local / 0.035, 3) }
        else if local < 0.09 { pulse = 1 }
        else if local < 0.22 { pulse = 1 - pow((local - 0.09) / 0.13, 2) }
        else { pulse = 0 }
        return min(1, max(0, pulse))
    }

    static func intensity(index: Int, elapsed: Double, seed: Int, state: ActivityState = .starting) -> Double {
        0.64 + solvingPulse(index: index, elapsed: elapsed, seed: seed, state: state) * 0.36
    }

    static func animates(_ cube: CubeDescriptor, at now: Date, enabled: Bool, visible: Bool) -> Bool {
        guard enabled, visible else { return false }
        let elapsed = max(0, now.timeIntervalSince(cube.epoch))
        if cube.state == .completed { return elapsed < completionDuration }
        if cube.state.needsAttention { return elapsed < 1.2 }
        return cube.state.isActive
    }

    // Reuse the solving pulse: glow and lit cell must never drift apart.
    static func glow(index: Int, elapsed: Double, seed: Int, state: ActivityState, enabled: Bool) -> Double {
        guard enabled, state.isActive, !state.needsAttention else { return 0 }
        return solvingPulse(index: index, elapsed: elapsed, seed: seed, state: state)
    }

    static func visibleCount(total: Int, wingWidth: CGFloat) -> Int {
        let capacity = min(3, max(1, Int((wingWidth + 6) / 28)))
        return total <= capacity ? total : min(capacity, max(1, Int((wingWidth - 20 + 0.1) / 28)))
    }
}

struct CubeCompanion: NSViewRepresentable {
    let descriptor: CubeDescriptor
    let paused: Bool
    var frozen = false
    @Environment(\.displayScale) private var displayScale

    func makeNSView(context: Context) -> CubeLayerView { CubeLayerView() }
    func updateNSView(_ view: CubeLayerView, context: Context) {
        view.update(descriptor, paused: paused, scale: displayScale, frozen: frozen)
    }
    static func dismantleNSView(_ view: CubeLayerView, coordinator: ()) { view.stop() }
}

@MainActor
final class CubeLayerView: NSView {
    private var tiles: [CAShapeLayer] = []
    private var glows: [CAShapeLayer] = []
    private var descriptor = CubeDescriptor.idle
    private var paused = false
    private var frozen = false
    private var scale: CGFloat = 2
    private var observer: NSObjectProtocol?
    private static let palette: [NSColor] = [
        .init(red: 0.20, green: 0.56, blue: 0.94, alpha: 1),
        .init(red: 0.95, green: 0.79, blue: 0.20, alpha: 1),
        .init(red: 0.93, green: 0.28, blue: 0.25, alpha: 1),
        .init(red: 0.22, green: 0.76, blue: 0.48, alpha: 1),
        .init(white: 0.94, alpha: 1),
        .init(red: 0.95, green: 0.52, blue: 0.20, alpha: 1),
        .init(red: 0.20, green: 0.75, blue: 0.83, alpha: 1),
        .init(red: 0.65, green: 0.48, blue: 0.90, alpha: 1)
    ]
    private static let solvedPalette = [3, 0, 1, 5, 6, 7]

    init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        layer?.masksToBounds = false
        // Put every halo behind the whole face, preserving crisp cell edges.
        for _ in 0..<9 {
            let glow = CAShapeLayer()
            glow.shadowOffset = .zero
            // Compact edge bloom, not a large diffuse cloud around the face.
            glow.shadowRadius = 1.4
            glow.shadowOpacity = 0.9
            glow.opacity = 0
            layer?.addSublayer(glow)
            glows.append(glow)
        }
        for _ in 0..<9 {
            let tile = CAShapeLayer()
            layer?.addSublayer(tile)
            tiles.append(tile)
        }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let face = min(bounds.width, bounds.height, 22)
        let pitch = (face - 2 + 0.75) / 3
        for i in 0..<9 {
            func snap(_ x: CGFloat) -> CGFloat { (x * scale).rounded() / scale }
            let x = snap((bounds.width - face) / 2 + 1 + CGFloat(i % 3) * pitch)
            let y = snap((bounds.height - face) / 2 + 1 + CGFloat(i / 3) * pitch)
            let size = snap(pitch - 0.75)
            tiles[i].frame = CGRect(x: x, y: y, width: size, height: size)
            tiles[i].path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                                  cornerWidth: 1.1, cornerHeight: 1.1, transform: nil)
            tiles[i].contentsScale = scale
            glows[i].frame = tiles[i].frame
            glows[i].path = tiles[i].path
            glows[i].shadowPath = tiles[i].path
            glows[i].contentsScale = scale
        }
        CATransaction.commit()
    }

    func update(_ descriptor: CubeDescriptor, paused: Bool, scale: CGFloat, frozen: Bool) {
        self.descriptor = descriptor
        self.paused = paused
        self.scale = max(1, scale)
        self.frozen = frozen
        needsLayout = true
        tick(at: Date())
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let window {
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                               object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(at: Date()) }
            }
        }
        tick(at: Date())
    }

    func stop() {
        CubeAnimationDriver.shared.remove(self)
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func tick(at now: Date) {
        let elapsed = frozen ? 0.24 : max(0, now.timeIntervalSince(descriptor.epoch))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let base = [0, 1, 2, 3, 4, 5, 2, 0, 1]
        for i in 0..<9 {
            var color = Self.palette[base[(i + descriptor.seed) % 9]]
            var intensity = 0.88
            if let solved = descriptor.solvedColor {
                let target = Self.palette[Self.solvedPalette[solved % 6]]
                let t = descriptor.state == .idle || paused ? 1 : CubeTimeline.completion(index: i, elapsed: elapsed)
                color = color.blended(withFraction: t, of: target) ?? target
                intensity = 0.9 + 0.1 * t
            } else if descriptor.state == .cancelled || descriptor.state == .failed {
                color = i == 4 ? (descriptor.state == .failed ? .systemRed : .systemGray) : NSColor(white: 0.35, alpha: 1)
            } else if descriptor.state.needsAttention {
                if i == 4 { color = .systemOrange }
                intensity = i == 4 ? 1 : 0.62
                if !paused, i == 4, elapsed < 1.2 { intensity = 0.8 + 0.2 * sin(elapsed / 1.2 * .pi) }
            } else if descriptor.state.isActive && !paused {
                intensity = CubeTimeline.intensity(index: i, elapsed: elapsed, seed: descriptor.seed, state: descriptor.state)
            }
            let glow = CubeTimeline.glow(
                index: i, elapsed: elapsed, seed: descriptor.seed,
                state: descriptor.state, enabled: !paused && descriptor.solvedColor == nil)
            let litColor = color.blended(withFraction: 0.14 * glow, of: .white) ?? color
            tiles[i].fillColor = litColor.cgColor
            tiles[i].opacity = Float(intensity)
            glows[i].fillColor = litColor.cgColor
            glows[i].shadowColor = litColor.cgColor
            glows[i].opacity = Float(0.8 * glow)
        }
        CATransaction.commit()
        let visible = window?.occlusionState.contains(.visible) == true && !isHiddenOrHasHiddenAncestor
        if CubeTimeline.animates(descriptor, at: now, enabled: !paused && !frozen, visible: visible) {
            CubeAnimationDriver.shared.add(self)
        } else { CubeAnimationDriver.shared.remove(self) }
    }
}

@MainActor
final class CubeAnimationDriver {
    static let shared = CubeAnimationDriver()
    private let views = NSHashTable<CubeLayerView>.weakObjects()
    private var timer: Timer?
    var isRunning: Bool { timer != nil }
    func add(_ view: CubeLayerView) {
        views.add(view)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                for view in self.views.allObjects { view.tick(at: now) }
                if self.views.allObjects.isEmpty { self.timer?.invalidate(); self.timer = nil }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func remove(_ view: CubeLayerView) {
        views.remove(view)
        if views.allObjects.isEmpty { timer?.invalidate(); timer = nil }
    }
}

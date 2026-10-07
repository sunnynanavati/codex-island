import Foundation
import CoreGraphics

@MainActor
struct RailPresentation: Equatable {
    private var roster = CubeRoster()
    private(set) var cubes: [CubeDescriptor] = [.idle]
    private(set) var label: String?
    private(set) var sizingLabel: String?
    private(set) var completionDeadline: Date?

    var usesWorkingWidth: Bool { label != nil || completionDeadline != nil }
    var accessibleStatus: String { label ?? "Idle" }

    mutating func update(snapshot: IslandSnapshot, now: Date, completionAnimated: Bool = true) {
        let wasWorking = label != nil
        let previousSizingLabel = sizingLabel
        let next = roster.reconcile(tasks: snapshot.tasks, now: now, retainCompleted: true)
        let live = next.filter { $0.state.isActive || $0.state.needsAttention }
        if !live.isEmpty {
            completionDeadline = nil
            cubes = next
            let primary = live.first { $0.id == snapshot.primaryTaskID }
                ?? live.first { $0.state.needsAttention } ?? live[0]
            label = IslandDesign.compactLabel(primary.state)
            sizingLabel = label
        } else {
            label = nil
            if wasWorking, completionAnimated, next.contains(where: { $0.state == .completed }) {
                cubes = next
                completionDeadline = now.addingTimeInterval(CubeTimeline.completionDuration)
                sizingLabel = previousSizingLabel
            } else if completionDeadline != nil, completionAnimated {
                cubes = next
                settle(at: now)
            } else {
                becomeIdle()
            }
        }
    }

    mutating func settle(at now: Date) {
        guard let completionDeadline, now >= completionDeadline else { return }
        becomeIdle()
    }

    private mutating func becomeIdle() {
        var cube = cubes.first(where: { $0.state == .completed || $0.state == .idle }) ?? .idle
        cube.state = .idle
        cube.solvedColor = 0
        cubes = [cube]
        label = nil
        sizingLabel = nil
        completionDeadline = nil
        roster = CubeRoster()
    }
}

struct RailGeometry: Equatable, Sendable {
    let cubeWidth: CGFloat
    let statusWidth: CGFloat
    let clearance: CGFloat

    var wingWidth: CGFloat { max(cubeWidth, statusWidth) + 2 * clearance }

    static func clearance(displayScale: CGFloat) -> CGFloat { 24 / max(1, displayScale) }

    static func cubeWidth(count: Int) -> CGFloat {
        let visible = min(3, max(1, count))
        // Reserve enough room for an overflow count even with many chats.
        let overflow: CGFloat = count > visible ? 6 + max(20, CGFloat(String(count - visible).count + 1) * 6) : 0
        return 22 + CGFloat(visible - 1) * 28 + overflow
    }

    static func statusOpacity(availableWing: CGFloat, displayedGroup: CGFloat,
                              requiredGroup: CGFloat, clearance: CGFloat) -> Double {
        let leftClearance = (availableWing + displayedGroup) / 2 - requiredGroup
        // Keep blur and glyph overhang clear of the notch throughout the reveal.
        let protected = min(4, clearance / 2)
        return Double(min(1, max(0, (leftClearance - protected) / max(1, clearance - protected))))
    }
}

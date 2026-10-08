import SwiftUI

enum TrayShimmer {
    static let duration = 2.5
    static func enabled(state: ActivityState, visible: Bool, animations: Bool, reducedMotion: Bool) -> Bool {
        visible && animations && !reducedMotion && state.isActive && !state.needsAttention
    }
    static func phase(at time: TimeInterval) -> Double {
        guard time.isFinite else { return 0 }
        let remainder = time.truncatingRemainder(dividingBy: duration)
        return (remainder < 0 ? remainder + duration : remainder) / duration
    }
}

struct TrayActivityText: View {
    let state: ActivityState
    let visible: Bool
    let animationsEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.colorSchemeContrast) private var colorContrast

    var body: some View {
        Group {
            if TrayShimmer.enabled(state: state, visible: visible, animations: animationsEnabled, reducedMotion: reducedMotion) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let phase = TrayShimmer.phase(at: context.date.timeIntervalSinceReferenceDate)
                    Text(state.label).foregroundStyle(LinearGradient(
                        stops: [.init(color: muted, location: 0), .init(color: muted, location: 0.3),
                                .init(color: .white, location: 0.5), .init(color: muted, location: 0.7),
                                .init(color: muted, location: 1)],
                        startPoint: UnitPoint(x: phase * 2 - 1, y: 0),
                        endPoint: UnitPoint(x: phase * 2, y: 0.35)))
                }
            } else {
                Text(state.label).foregroundStyle(state.needsAttention || state == .failed
                                                 ? IslandDesign.color(state) : muted)
            }
        }
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(state.label)
    }

    private var muted: Color { colorContrast == .increased ? .white : IslandDesign.secondary }
}

struct ProjectFolderIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 24, y: rect.minY + rect.height * y / 24)
        }
        path.move(to: p(3, 18))
        path.addLine(to: p(2, 6))
        path.addQuadCurve(to: p(4, 4), control: p(2, 4))
        path.addLine(to: p(9, 4))
        path.addLine(to: p(12, 7))
        path.addLine(to: p(19, 7))
        path.addQuadCurve(to: p(21, 9), control: p(21, 7))
        path.addLine(to: p(21, 10))
        path.move(to: p(3, 18))
        path.addLine(to: p(6, 11))
        path.addQuadCurve(to: p(8, 10), control: p(6.5, 10))
        path.addLine(to: p(22, 10))
        path.addLine(to: p(18, 19))
        path.addQuadCurve(to: p(16, 20), control: p(17.5, 20))
        path.addLine(to: p(5, 20))
        path.addQuadCurve(to: p(3, 18), control: p(3, 20))
        return path
    }
}

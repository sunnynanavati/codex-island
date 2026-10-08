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

    static func state(for label: String) -> ActivityState {
        ActivityState.allCases.first { $0.label == label || IslandDesign.compactLabel($0) == label } ?? .idle
    }
}

/// The same absolute-time sweep is used by rail phrases and every tray status.
struct ActivityShimmerStyle: ViewModifier {
    let state: ActivityState
    let visible: Bool
    let animationsEnabled: Bool
    let reducedMotion: Bool
    let increasedContrast: Bool

    func body(content: Content) -> some View {
        Group {
            if TrayShimmer.enabled(state: state, visible: visible, animations: animationsEnabled, reducedMotion: reducedMotion) {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let phase = TrayShimmer.phase(at: context.date.timeIntervalSinceReferenceDate)
                    content.foregroundStyle(LinearGradient(
                        stops: [.init(color: muted, location: 0), .init(color: muted, location: 0.3),
                                .init(color: .white, location: 0.5), .init(color: muted, location: 0.7),
                                .init(color: muted, location: 1)],
                        startPoint: UnitPoint(x: phase * 2 - 1, y: 0.5),
                        endPoint: UnitPoint(x: phase * 2, y: 0.5)))
                }
            } else {
                content.foregroundStyle(state.needsAttention ? IslandDesign.color(state) : muted)
            }
        }
    }

    private var muted: Color { increasedContrast ? .white : IslandDesign.secondary }
}

struct TrayActivityText: View {
    let state: ActivityState
    let visible: Bool
    let animationsEnabled: Bool
    var reduceMotionOverride: Bool? = nil
    var increasedContrastOverride: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.colorSchemeContrast) private var colorContrast

    var body: some View {
        Text(state.label)
        .font(TrayFont.font(size: 12))
        .tracking(TrayFont.smallTextTracking)
        .modifier(ActivityShimmerStyle(state: state, visible: visible, animationsEnabled: animationsEnabled,
                                       reducedMotion: reduceMotionOverride ?? reducedMotion,
                                       increasedContrast: increasedContrastOverride ?? (colorContrast == .increased)))
        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        .help(state.label).accessibilityLabel(state.label)
    }

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

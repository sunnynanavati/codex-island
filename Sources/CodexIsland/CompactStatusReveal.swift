import SwiftUI

/// Native adaptation of beUI Text Reveal: one word slides upward into place.
struct CompactStatusReveal: View {
    let label: String
    let font: Font
    let fontSize: CGFloat
    let motionEnabled: Bool
    let reduceMotion: Bool
    var shimmerVisible = true
    var increasedContrast = false
    @State private var progress = 1.0

    var body: some View {
        Text(label).font(font)
            .modifier(ActivityShimmerStyle(state: TrayShimmer.state(for: label), visible: shimmerVisible,
                                           animationsEnabled: motionEnabled, reducedMotion: reduceMotion,
                                           increasedContrast: increasedContrast))
            .lineLimit(1).minimumScaleFactor(0.88)
            .modifier(StatusRevealFrame(progress: progress, fontSize: fontSize, reduceMotion: reduceMotion))
            .accessibilityLabel(label).help(label)
            .task(id: label) {
                guard motionEnabled else { settle(); return }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { progress = 0 }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .easeOut(duration: IslandDesign.statusFadeDuration)
                              : .interpolatingSpring(mass: 1.2, stiffness: 140, damping: 26, initialVelocity: 0)) {
                    progress = 1
                }
            }
            .onChange(of: motionEnabled) { _, enabled in if !enabled { settle() } }
            .onChange(of: reduceMotion) { _, _ in settle() }
            .onDisappear { settle() }
    }

    private func settle() {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { progress = 1 }
    }
}

struct StatusRevealFrame: ViewModifier, @preconcurrency Animatable {
    var progress: Double
    let fontSize: CGFloat
    let reduceMotion: Bool
    var animatableData: Double { get { progress } set { progress = newValue } }
    private var phase: Double { min(1, max(0, progress)) }
    var offset: CGFloat { reduceMotion ? 0 : fontSize * 0.4 * (1 - phase) }
    var blurRadius: Double { reduceMotion ? 0 : 3 * (1 - phase) }
    var alpha: Double { phase }
    func body(content: Content) -> some View {
        content.offset(y: offset).blur(radius: blurRadius).opacity(alpha)
    }
}

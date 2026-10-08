import SwiftUI

struct CompactStatusFlip: View {
    let label: String
    let font: Font
    let motionEnabled: Bool
    let reduceMotion: Bool
    var shimmerVisible = true
    var increasedContrast = false
    var style: StatusTransitionStyle = .fold
    var duration = 0.28
    var blur = 3.0
    @State private var shown = ""
    @State private var outgoing: String?
    @State private var progress = 1.0

    private var fadeOnly: Bool { reduceMotion || style == .fade }
    private var transitionDuration: Double { reduceMotion ? IslandDesign.statusFadeDuration : duration }

    var body: some View {
        ZStack {
            if let outgoing {
                phrase(outgoing).modifier(StatusFlipFrame(progress: progress, entering: false,
                                                         reduceMotion: fadeOnly, peakBlur: blur))
            }
            phrase(shown.isEmpty ? label : shown)
                .modifier(StatusFlipFrame(progress: progress, entering: true,
                                          reduceMotion: fadeOnly, peakBlur: blur))
        }
        .task(id: label) {
            guard shown != label else { return }
            guard !shown.isEmpty, motionEnabled, style != .instant else {
                outgoing = nil; shown = label; progress = 1
                return
            }
            // Only two phrase layers exist, even if polling changes labels mid-transition.
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { outgoing = shown; shown = label; progress = 0 }
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: transitionDuration)) { progress = 1 }
            do { try await Task.sleep(for: .seconds(transitionDuration)) } catch { return }
            outgoing = nil
        }
        .onChange(of: motionEnabled) { _, enabled in
            if !enabled {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { outgoing = nil; shown = label; progress = 1 }
            }
        }
        .onDisappear { outgoing = nil; progress = 1 }
    }

    private func phrase(_ text: String) -> some View {
        Text(text).font(font)
            .modifier(ActivityShimmerStyle(state: TrayShimmer.state(for: text), visible: shimmerVisible,
                                           animationsEnabled: motionEnabled, reducedMotion: reduceMotion,
                                           increasedContrast: increasedContrast))
            .lineLimit(1).minimumScaleFactor(0.88)
            .help(text)
    }
}
struct StatusFlipFrame: ViewModifier, @preconcurrency Animatable {
    var progress: Double
    let entering: Bool
    let reduceMotion: Bool
    var peakBlur = 3.0

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var verticalScale: Double {
        guard !reduceMotion else { return 1 }
        let foldedScale = 0.08
        return entering
            ? foldedScale + (1 - foldedScale) * flipPhase
            : 1 - (1 - foldedScale) * flipPhase
    }

    var blurRadius: Double {
        guard !reduceMotion else { return 0 }
        let rampIn = min(1, max(0, flipPhase / 0.25))
        let rampOut = min(1, max(0, (1 - flipPhase) / 0.25))
        func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }
        return peakBlur * min(smooth(rampIn), smooth(rampOut))
    }

    var alpha: Double {
        if reduceMotion { return entering ? clampedProgress : 1 - clampedProgress }
        return entering
            ? min(1, flipPhase / 0.28)
            : min(1, (1 - flipPhase) / 0.28)
    }

    private var clampedProgress: Double { min(1, max(0, progress)) }
    // The phrases occupy opposite halves of the turn, so the
    // letterforms do not dissolve over one another at the narrow notch size.
    private var flipPhase: Double {
        min(1, max(0, entering ? 2 * clampedProgress - 1 : 2 * clampedProgress))
    }

    func body(content: Content) -> some View {
        return content
            .scaleEffect(x: 1, y: verticalScale, anchor: .center)
            .blur(radius: blurRadius)
            .opacity(alpha)
    }
}

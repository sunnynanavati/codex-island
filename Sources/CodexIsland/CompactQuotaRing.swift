import SwiftUI

struct CompactQuotaState: Equatable {
    let percentage: Int?
    let fraction: Double
    let isCritical: Bool

    init(quota: QuotaWindow?) {
        guard let quota, quota.usedPercent.isFinite else {
            percentage = nil
            fraction = 0
            isCritical = false
            return
        }
        let remaining = quota.remainingPercent
        percentage = Int(remaining.rounded(.down))
        fraction = remaining / 100
        isCritical = QuotaSeverity(quota: quota) == .critical
    }

    var displayText: String { percentage.map(String.init) ?? "–" }
    var accessibilityLabel: String {
        percentage.map { "Codex quota, \($0) percent remaining" } ?? "Codex quota unavailable"
    }
}

struct CompactQuotaRing: View {
    static let diameter = CompactRailSizing.quotaDiameter
    static let strokeWidth: CGFloat = 1.2

    static func numberSize(for percentage: Int?, preferredSize: CGFloat) -> CGFloat {
        percentage == 100 ? preferredSize * (7 / 8.5) : preferredSize
    }

    let quota: QuotaWindow?
    let animationsEnabled: Bool
    let increasedContrast: Bool
    let typography: CompactTypography
    var fontFamily: IslandFontFamily = .nunito
    var ringStroke: CGFloat = 1.2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: CompactQuotaState { .init(quota: quota) }
    private var ringColor: Color { state.isCritical ? IslandDesign.red : .white }
    private var trackColor: Color {
        if state.isCritical { return IslandDesign.red.opacity(increasedContrast ? 0.65 : 0.48) }
        return .white.opacity(increasedContrast ? 0.48 : 0.25)
    }

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: ringStroke)
            if state.percentage != nil {
                Circle()
                    .trim(from: 0, to: state.fraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(state.displayText)
                .font(IslandFont.font(weight: typography.quotaWeight,
                                      size: Self.numberSize(for: state.percentage,
                                                            preferredSize: CGFloat(typography.quotaSize)),
                                      family: fontFamily))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .padding(ringStroke / 2)
        .animation(animationsEnabled && !reduceMotion ? .easeOut(duration: 0.24) : nil,
                   value: state.fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
    }
}

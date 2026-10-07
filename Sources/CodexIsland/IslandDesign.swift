import SwiftUI

struct IslandShape: Shape {
    var radius: CGFloat
    var shoulderReach: CGFloat
    var shoulderHeight: CGFloat
    var shoulderBlend: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(IslandContour.path(size: rect.size, radius: radius,
                                shoulderReach: shoulderReach, shoulderHeight: shoulderHeight,
                                shoulderBlend: shoulderBlend))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

enum IslandDesign {
    static let secondary = Color(white: 0.67)
    static let surface = Color(white: 0.075)
    static let green = Color(red: 0.49, green: 0.89, blue: 0.67)
    static let amber = Color(red: 1, green: 0.76, blue: 0.40)
    static let red = Color(red: 1, green: 0.46, blue: 0.48)
    static let labelDuration = 0.14
    static let statusFlipDuration = 0.28
    static let statusFadeDuration = 0.18
    static let pressDuration = 0.12

    static func color(_ state: ActivityState) -> Color {
        if state == .failed { return red }
        if state.needsAttention { return amber }
        if state.isActive || state == .completed { return green }
        return secondary
    }
    static func symbol(_ state: ActivityState) -> String {
        switch state {
        case .starting: "sparkle"
        case .planning: "list.bullet.clipboard"
        case .thinking: "brain"
        case .reading: "doc.text"
        case .scanning: "square.stack.3d.up"
        case .searching: "magnifyingglass"
        case .editing, .writing: "pencil.line"
        case .running: "terminal"
        case .waitingForInput, .attentionRequired: "exclamationmark.bubble"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        case .cancelled: "stop.circle"
        case .idle: "circle.dotted"
        }
    }
    static func compactLabel(_ state: ActivityState) -> String {
        switch state {
        case .waitingForInput: "Your turn"
        case .attentionRequired: "Attention"
        case .running: "Running"
        case .completed: "Done"
        default: state.label
        }
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes == 0 { return "<1m" }
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct IslandPressStyle: ButtonStyle {
    var motionEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(configuration.isPressed && motionEnabled && !reduceMotion ? 0.98 : 1)
            .animation(motionEnabled ? .easeOut(duration: IslandDesign.pressDuration) : nil,
                       value: configuration.isPressed)
    }
}

struct IslandButton<Label: View>: View {
    var motionEnabled = true
    var focusRequested = false
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @FocusState private var focused: Bool
    @State private var hovered = false
    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(IslandPressStyle(motionEnabled: motionEnabled))
            .focusable()
            .focused($focused)
            .onKeyPress(.space) { action(); return .handled }
            .onKeyPress(.return) { action(); return .handled }
            .onChange(of: focusRequested, initial: true) { _, requested in
                if requested { focused = true }
            }
            .background(hovered ? Color.white.opacity(0.055) : .clear,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? Color.white.opacity(0.9) : .clear, lineWidth: 2))
            .onHover { hovered = $0 }
    }
}

import AppKit
import SwiftUI

struct TrayAge: Equatable {
    let value: Int
    let unit: String

    init(date: Date, now: Date) {
        let interval = now.timeIntervalSince(date)
        let minutes = interval.isFinite ? max(1, Int(max(0, interval) / 60)) : 1
        if minutes >= 1440 { value = minutes / 1440; unit = "d" }
        else if minutes >= 60 { value = minutes / 60; unit = "h" }
        else { value = minutes; unit = "m" }
    }
    var label: String { "\(value)\(unit) ago" }
}

struct TrayBullet: View {
    var body: some View {
        Circle().fill(.white).frame(width: 2, height: 2).accessibilityHidden(true)
    }
}

/// Native, place-value-stable rolling columns. First render is static; only value changes roll.
struct TrayNumberTicker: View {
    let value: Int
    let motionEnabled: Bool
    var size: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    static func digits(_ value: Int) -> [Int] { String(max(0, value)).compactMap { $0.wholeNumberValue }.reversed() }

    var body: some View {
        Group {
            if motionEnabled && !reducedMotion {
                let digits = Self.digits(value)
                HStack(spacing: 0) {
                    ForEach(Array(digits.indices.reversed()), id: \.self) { place in
                        VStack(spacing: 0) {
                            ForEach(0..<10) { digit in
                                Text("\(digit)").frame(width: digitWidth, height: size * 1.3)
                            }
                        }
                        .offset(y: -CGFloat(digits[place]) * size * 1.3)
                        .frame(width: digitWidth, height: size * 1.3, alignment: .top)
                        .clipped()
                        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.9), value: digits[place])
                    }
                }
            } else {
                Text("\(max(0, value))").contentTransition(.opacity)
                    .animation(motionEnabled ? .easeOut(duration: 0.12) : nil, value: value)
            }
        }
        .font(.system(size: size)).monospacedDigit()
        .accessibilityElement(children: .ignore).accessibilityLabel("\(max(0, value))")
    }
    private var digitWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)]).width
    }
}

struct TrayRelativeTime: View {
    let date: Date
    let now: Date
    let visible: Bool
    let motionEnabled: Bool
    var size: CGFloat = 11

    var body: some View {
        Group {
            if visible {
                TimelineView(.periodic(from: .now, by: 60)) { context in label(at: context.date) }
            } else { label(at: now) }
        }
        .fixedSize()
    }
    private func label(at now: Date) -> some View {
        let age = TrayAge(date: date, now: now)
        return HStack(spacing: 0) {
            TrayNumberTicker(value: age.value, motionEnabled: motionEnabled && visible, size: size)
            Text("\(age.unit) ago").font(.system(size: size))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(age.label)
        .help(date.formatted(date: .abbreviated, time: .shortened))
    }
}

enum CodexUnreadState {
    /// Read-only Codex desktop state. Unknown schema or multiple account identities is unavailable.
    static func count(data: Data, excluding childIDs: Set<String>) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = root["electron-thread-read-state-v1"] as? [String: Any],
              state["version"] as? Int == 1,
              let identities = state["unreadByIdentity"] as? [String: [String: [String]]],
              identities.count <= 1 else { return nil }
        var ids: Set<String> = []
        for hosts in identities.values {
            for (host, unread) in hosts where host.hasPrefix("local:") {
                ids.formUnion(unread.filter { UUID(uuidString: $0) != nil })
            }
        }
        return ids.subtracting(childIDs).count
    }
}

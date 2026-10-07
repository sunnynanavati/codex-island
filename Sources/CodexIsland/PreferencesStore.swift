import Foundation
import SwiftUI

enum IslandFontFamily: String, Codable, CaseIterable { case nunito, system
    var title: String { self == .nunito ? "Nunito" : "System" }
}
enum StatusTransitionStyle: String, Codable, CaseIterable { case fold, fade, instant
    var title: String { rawValue.capitalized }
}
enum IslandAccent: String, Codable, CaseIterable { case green, blue, purple, system
    var title: String { rawValue.capitalized }
    var color: Color { switch self {
    case .green: IslandDesign.green
    case .blue: .blue
    case .purple: .purple
    case .system: .accentColor
    } }
}

struct IslandPreferences: Codable, Equatable {
    var calibration = Calibration()
    var typography = CompactTypography()
    var glyphTheme = IslandGlyphTheme.cube
    var fontFamily = IslandFontFamily.nunito
    var accent = IslandAccent.green
    var animationsEnabled = true
    var cubeAnimationsEnabled = true
    var showIsland = true
    var hoverPreviewEnabled = true
    var statusGap = 9.0
    var ringStroke = 1.2
    var statusTransition = StatusTransitionStyle.fold
    var statusDuration = 0.28
    var statusBlur = 3.0
    var hoverEntryMS = 120.0
    var hoverExitMS = 220.0
    var springSpeed = 1.0

    var normalized: Self {
        var result = self
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        result.typography = typography.normalized
        result.statusGap = clamp(statusGap, 6...16, 9)
        result.ringStroke = clamp(ringStroke, 0.8...1.8, 1.2)
        result.statusDuration = clamp(statusDuration, 0.18...0.3, 0.28)
        result.statusBlur = clamp(statusBlur, 0...3, 3)
        result.hoverEntryMS = clamp(hoverEntryMS, 80...400, 120)
        result.hoverExitMS = clamp(hoverExitMS, 100...500, 220)
        result.springSpeed = clamp(springSpeed, 0.8...1.2, 1)
        result.calibration.horizontalOffset = clamp(calibration.horizontalOffset, -120...120, 0)
        result.calibration.widthAdjustment = clamp(calibration.widthAdjustment, -120...120, 0)
        result.calibration.shoulderReach = clamp(calibration.shoulderReach, 0...140, 100)
        result.calibration.compactSize = clamp(calibration.compactSize, 0...1, 0)
        result.calibration.waveReach = calibration.waveReach.map { clamp($0, 40...220, 140) }
        return result
    }
}

struct AppearancePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var values: IslandPreferences
}

@MainActor
final class PreferencesStore: ObservableObject {
    static let key = "CodexIsland.preferences.v1"
    static let presetsKey = "CodexIsland.presets.v1"
    private let defaults: UserDefaults?
    @Published var values: IslandPreferences {
        didSet {
            guard values != oldValue else { return }
            if values != values.normalized { values = values.normalized }
            persist()
        }
    }
    @Published var presets: [AppearancePreset] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(presets) { defaults?.set(data, forKey: Self.presetsKey) }
        }
    }

    init(defaults: UserDefaults? = PreferencesStore.appDefaults, initial: IslandPreferences? = nil) {
        self.defaults = defaults
        if let initial { values = initial.normalized; return }
        if let data = defaults?.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(IslandPreferences.self, from: data) {
            values = saved.normalized
        } else {
            var migrated = IslandPreferences()
            if let defaults {
                migrated.calibration = Calibration.load(from: defaults)
                migrated.typography = CompactTypography.load(from: defaults)
                migrated.animationsEnabled = defaults.object(forKey: "animationsEnabled") as? Bool ?? true
                migrated.glyphTheme = IslandGlyphTheme(rawValue: defaults.string(forKey: "glyphTheme") ?? "cube") ?? .cube
            }
            values = migrated.normalized
        }
        if let data = defaults?.data(forKey: Self.presetsKey),
           let saved = try? JSONDecoder().decode([AppearancePreset].self, from: data) { presets = saved }
        persist()
    }

    static var appDefaults: UserDefaults {
        // swift run has no bundle identifier. Keep its experiments out of release preferences.
        if let identifier = Bundle.main.bundleIdentifier,
           ["com.codexisland.app", "com.codexisland.dev"].contains(identifier) {
            return .standard
        }
        return UserDefaults(suiteName: "com.codexisland.dev") ?? .standard
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(values) { defaults?.set(data, forKey: Self.key) }
    }
    func savePreset(name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty else { return }
        var appearance = values
        appearance.showIsland = true
        presets.append(.init(id: UUID(), name: name, values: appearance))
    }
    func applyPreset(_ preset: AppearancePreset) {
        let visible = values.showIsland
        values = preset.values.normalized
        values.showIsland = visible
    }
    func renamePreset(id: UUID, name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
    }
    func duplicatePreset(id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        presets.append(.init(id: UUID(), name: preset.name + " copy", values: preset.values))
    }
    func deletePreset(id: UUID) { presets.removeAll { $0.id == id } }
    func resetAll() { values = .init() }
    func resetLayout() { values.calibration = .init(); values.statusGap = 9; values.ringStroke = 1.2 }
    func resetAppearance() {
        values.typography = .init(); values.glyphTheme = .cube; values.fontFamily = .nunito; values.accent = .green
    }
    func resetMotion() {
        values.animationsEnabled = true; values.cubeAnimationsEnabled = true
        values.statusTransition = .fold; values.statusDuration = 0.28; values.statusBlur = 3
        values.hoverPreviewEnabled = true; values.hoverEntryMS = 120; values.hoverExitMS = 220; values.springSpeed = 1
    }
}

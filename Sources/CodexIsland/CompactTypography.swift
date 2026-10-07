import Foundation

enum CompactFontWeight: String, CaseIterable, Codable, Sendable {
    case light
    case regular
    case semibold

    var title: String {
        switch self {
        case .light: "Light"
        case .regular: "Regular"
        case .semibold: "Semibold"
        }
    }
}

struct CompactTypography: Codable, Equatable, Sendable {
    static let defaultsKey = "CodexIsland.compactTypography"
    static let statusSizeRange = 10.0...14.0
    static let quotaSizeRange = 7.5...10.5

    var statusSize: Double = 12
    var statusWeight: CompactFontWeight = .regular
    var quotaSize: Double = 8.5
    var quotaWeight: CompactFontWeight = .regular

    private enum CodingKeys: String, CodingKey {
        case statusSize, statusWeight, quotaSize, quotaWeight
    }

    init(statusSize: Double = 12, statusWeight: CompactFontWeight = .regular,
         quotaSize: Double = 8.5, quotaWeight: CompactFontWeight = .regular) {
        self.statusSize = statusSize
        self.statusWeight = statusWeight
        self.quotaSize = quotaSize
        self.quotaWeight = quotaWeight
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        statusSize = try values.decodeIfPresent(Double.self, forKey: .statusSize) ?? 12
        statusWeight = try values.decodeIfPresent(CompactFontWeight.self, forKey: .statusWeight) ?? .regular
        quotaSize = try values.decodeIfPresent(Double.self, forKey: .quotaSize) ?? 8.5
        quotaWeight = try values.decodeIfPresent(CompactFontWeight.self, forKey: .quotaWeight) ?? .regular
        self = normalized
    }

    var normalized: Self {
        var value = self
        value.statusSize = Self.clamp(statusSize, to: Self.statusSizeRange, fallback: 12)
        value.quotaSize = Self.clamp(quotaSize, to: Self.quotaSizeRange, fallback: 8.5)
        return value
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(normalized) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return value
    }
}

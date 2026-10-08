import AppKit
import CoreText
import SwiftUI

@MainActor
enum IslandFont {
    static let postScriptName = "Nunito-SemiBold"
    static let lightPostScriptName = "Nunito-Light"
    static let regularPostScriptName = "Nunito-Regular"
    private(set) static var isAvailable = false
    private(set) static var isLightAvailable = false
    private(set) static var isRegularAvailable = false

    static func register() {
        isAvailable = registerFont(named: postScriptName)
        isLightAvailable = registerFont(named: lightPostScriptName)
        isRegularAvailable = registerFont(named: regularPostScriptName)
        TrayFont.register()
    }

    private static func registerFont(named name: String) -> Bool {
        guard let url = Bundle.main.url(forResource: name, withExtension: "ttf")
            ?? Bundle.module.url(forResource: name, withExtension: "ttf") else {
            AppLog.write("Bundled \(name) font is unavailable; using the system font")
            return false
        }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            || NSFont(name: name, size: 12) != nil {
            return true
        } else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "Unknown font registration error"
            AppLog.write("Could not register \(name) font: \(reason)")
            return false
        }
    }

    static func semibold(size: CGFloat) -> Font {
        isAvailable ? .custom(postScriptName, fixedSize: size) : .system(size: size, weight: .semibold)
    }

    static func light(size: CGFloat) -> Font {
        isLightAvailable ? .custom(lightPostScriptName, fixedSize: size) : .system(size: size, weight: .light)
    }

    static func regular(size: CGFloat) -> Font {
        isRegularAvailable ? .custom(regularPostScriptName, fixedSize: size) : .system(size: size, weight: .regular)
    }

    static func font(weight: CompactFontWeight, size: CGFloat, family: IslandFontFamily = .nunito) -> Font {
        if family == .system { return Font(nsFont(weight: weight, size: size, family: family)) }
        return switch weight {
        case .light: light(size: size)
        case .regular: regular(size: size)
        case .semibold: semibold(size: size)
        }
    }

    static func nsFont(weight: CompactFontWeight, size: CGFloat, family: IslandFontFamily = .nunito) -> NSFont {
        let name: String
        let fallbackWeight: NSFont.Weight
        switch weight {
        case .light: name = lightPostScriptName; fallbackWeight = .light
        case .regular: name = regularPostScriptName; fallbackWeight = .regular
        case .semibold: name = postScriptName; fallbackWeight = .semibold
        }
        return (family == .nunito ? NSFont(name: name, size: size) : nil) ?? .systemFont(ofSize: size, weight: fallbackWeight)
    }
}

/// Penpot tray typography is independent of the user's compact-rail typography.
@MainActor
enum TrayFont {
    static let smallTextTracking: CGFloat = 0.18
    private(set) static var isAvailable = false

    static func register() {
        guard let url = Bundle.main.url(forResource: "InterTight", withExtension: "ttf")
            ?? Bundle.module.url(forResource: "InterTight", withExtension: "ttf") else { return }
        var error: Unmanaged<CFError>?
        isAvailable = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            || NSFont(name: "InterTight-Regular", size: 12) != nil
        if !isAvailable { AppLog.write("Inter Tight registration failed; using system tray typography") }
    }

    static func nsFont(size: CGFloat, weight: Font.Weight = .regular) -> NSFont {
        guard isAvailable else {
            return .systemFont(ofSize: size, weight: weight == .semibold ? .semibold : weight == .medium ? .medium : .regular)
        }
        let axisWeight = weight == .semibold ? 600 : weight == .medium ? 500 : 400
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: "InterTight-Regular",
            kCTFontVariationAttribute: [NSNumber(value: 0x77676874): NSNumber(value: axisWeight)]
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(nsFont(size: size, weight: weight))
    }
}

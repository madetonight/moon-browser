import AppKit
import SwiftUI

/// Only opaque sRGB colors are persisted; never archived platform objects.
struct ChromeColorSet: Codable, Equatable {
    var background: String
    var foreground: String
    var text: String
    var accent: String?

    static let light = ChromeColorSet(background: "F4F4F4", foreground: "E4E4E4", text: "171717")
    static let dark = ChromeColorSet(background: "131313", foreground: "282828", text: "EDEDED")

    static func color(_ hex: String) -> NSColor? {
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }), let rgb = UInt32(hex, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> Int { Int((min(1, max(0, component)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    func validated(or fallback: ChromeColorSet) -> ChromeColorSet {
        .init(background: Self.color(background) == nil ? fallback.background : background.uppercased(),
              foreground: Self.color(foreground) == nil ? fallback.foreground : foreground.uppercased(),
              text: Self.color(text) == nil ? fallback.text : text.uppercased(),
              accent: accent.flatMap { Self.color($0) == nil ? nil : $0.uppercased() })
    }
}

struct ChromeColors: Codable, Equatable {
    static let key = "appearance.colors"
    var enabled = false
    var light = ChromeColorSet.light
    var dark = ChromeColorSet.dark
    static let standard = ChromeColors()

    static func load(from defaults: UserDefaults) -> ChromeColors {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Self.self, from: data) else { return .standard }
        return .init(enabled: saved.enabled, light: saved.light.validated(or: .light), dark: saved.dark.validated(or: .dark))
    }
}

/// Cache a new dynamic color per role only when the palette changes. SwiftUI
/// sees a new color identity and native fields resolve against their appearance.
enum ChromePalette {
    enum Role: Hashable {
        case ground, frame, ink, muted, faint, hairline, wash, hover, pinLive
        case sideWash, sideHover, sideTile, sidePinLive, resting, accent
    }
    private final class State: @unchecked Sendable {
        let lock = NSRecursiveLock()
        var colors = ChromeColors.load(from: Store.settings)
        var cache: [Role: NSColor] = [:]
    }
    private static let state = State()

    static func install(_ colors: ChromeColors) {
        state.lock.lock(); defer { state.lock.unlock() }
        guard colors != state.colors else { return }
        state.colors = colors
        state.cache.removeAll()
    }

    static func color(_ role: Role, light: CGFloat, dark: CGFloat) -> NSColor {
        state.lock.lock(); defer { state.lock.unlock() }
        if let saved = state.cache[role] { return saved }
        let colors = state.colors
        let made = NSColor(name: nil) { appearance in
            let dim = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            guard colors.enabled else { return NSColor(white: dim ? dark : light, alpha: 1) }
            let set = dim ? colors.dark : colors.light
            let fallback = dim ? ChromeColorSet.dark : .light
            let bg = ChromeColorSet.color(set.background) ?? ChromeColorSet.color(fallback.background)!
            let fg = ChromeColorSet.color(set.foreground) ?? ChromeColorSet.color(fallback.foreground)!
            let text = ChromeColorSet.color(set.text) ?? ChromeColorSet.color(fallback.text)!
            func blend(_ other: NSColor, _ fraction: CGFloat) -> NSColor { bg.blended(withFraction: fraction, of: other) ?? other }
            switch role {
            case .ground, .frame: return bg
            case .ink: return text
            case .muted: return blend(text, 0.64)
            case .faint, .resting: return blend(text, 0.30)
            case .hairline: return blend(text, 0.17)
            case .wash, .pinLive, .sideWash, .sidePinLive: return fg
            case .hover, .sideHover: return blend(fg, 0.55)
            case .sideTile: return blend(fg, 0.40)
            case .accent: return set.accent.flatMap(ChromeColorSet.color) ?? text
            }
        }
        state.cache[role] = made
        return made
    }
}

struct ChromeColorsEditor: View {
    @ObservedObject var prefs: Preferences
    @State private var dark = false
    @Environment(\.colorScheme) private var scheme

    private var set: ChromeColorSet { dark ? prefs.chromeColors.dark : prefs.chromeColors.light }
    private func change(_ action: (inout ChromeColorSet) -> Void) {
        var colors = prefs.chromeColors
        if dark { action(&colors.dark) } else { action(&colors.light) }
        prefs.chromeColors = colors
    }
    private func binding(_ key: WritableKeyPath<ChromeColorSet, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: ChromeColorSet.color(set[keyPath: key]) ?? .black) },
                set: { color in
                    guard let hex = ChromeColorSet.hex(NSColor(color)) else { return }
                    change { $0[keyPath: key] = hex }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Custom colors").font(.system(size: 12.5)).foregroundStyle(Palette.ink)
                Spacer()
                Switch(on: Binding(get: { prefs.chromeColors.enabled }, set: { prefs.chromeColors.enabled = $0 }))
                    .accessibilityLabel("Custom colors")
            }
            if prefs.chromeColors.enabled {
                Picker("Palette to edit", selection: $dark) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 240)
                ColorPicker("Background", selection: binding(\.background), supportsOpacity: false)
                ColorPicker("Foreground", selection: binding(\.foreground), supportsOpacity: false)
                Text("Foreground colors tabs, buttons and raised surfaces.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                ColorPicker("Text", selection: binding(\.text), supportsOpacity: false)
                HStack {
                    Text("Optional accent").foregroundStyle(Palette.ink)
                    Spacer()
                    Switch(on: Binding(get: { set.accent != nil }, set: { on in change { $0.accent = on ? "4C8DFF" : nil } }))
                        .accessibilityLabel("Optional accent")
                }
                if set.accent != nil {
                    ColorPicker("Accent", selection: Binding(
                        get: { Color(nsColor: set.accent.flatMap(ChromeColorSet.color) ?? .systemBlue) },
                        set: { color in guard let hex = ChromeColorSet.hex(NSColor(color)) else { return }; change { $0.accent = hex } }
                    ), supportsOpacity: false)
                }
            }
            Button("Reset colors to Moon defaults") { prefs.chromeColors = .standard }
                .buttonStyle(.bordered)
                .foregroundStyle(Color.primary)
                .background(Color(nsColor: .windowBackgroundColor), in: Capsule())
                .disabled(prefs.chromeColors == .standard)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.ink)
        .onAppear { dark = scheme == .dark }
    }
}

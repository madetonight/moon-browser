import AppKit
import XCTest
@testable import Moon

@MainActor
final class ChromeColorsTests: XCTestCase {
    private func resolved(_ color: NSColor, dark: Bool) throws -> NSColor {
        let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance { result = color.usingColorSpace(.sRGB) }
        return try XCTUnwrap(result)
    }

    func testOpaqueRGBValidationRejectsMalformedAndTransparentValues() {
        for invalid in ["#123456", "12345", "12345678", "ZZZZZZ", "１２３４５６"] {
            XCTAssertNil(ChromeColorSet.color(invalid))
        }
        XCTAssertEqual(ChromeColorSet.hex(ChromeColorSet.color("12abef")!), "12ABEF")
    }

    func testBothAppearancesResolveTheirOwnPalette() throws {
        defer { ChromePalette.install(.standard) }
        var colors = ChromeColors.standard
        colors.enabled = true
        colors.light.background = "E0F0FF"
        colors.dark.background = "001122"
        colors.dark.foreground = "123456"
        colors.dark.text = "ABCDEF"
        ChromePalette.install(colors)
        XCTAssertEqual(ChromeColorSet.hex(try resolved(Palette.NS.ground, dark: false)), "E0F0FF")
        XCTAssertEqual(ChromeColorSet.hex(try resolved(Palette.NS.frame, dark: true)), "001122")
        XCTAssertEqual(ChromeColorSet.hex(try resolved(Palette.NS.sideWash, dark: true)), "123456")
        XCTAssertEqual(ChromeColorSet.hex(try resolved(Palette.NS.ink, dark: true)), "ABCDEF")
    }

    func testOptionalAccentAndResetInvalidateCachedColors() throws {
        defer { ChromePalette.install(.standard) }
        var colors = ChromeColors.standard; colors.enabled = true
        ChromePalette.install(colors)
        let previous = Palette.NS.accent
        XCTAssertEqual(ChromeColorSet.hex(try resolved(previous, dark: true)), colors.dark.text)
        colors.dark.accent = "4080FF"; ChromePalette.install(colors)
        XCTAssertFalse(previous === Palette.NS.accent)
        XCTAssertEqual(ChromeColorSet.hex(try resolved(Palette.NS.accent, dark: true)), "4080FF")
        ChromePalette.install(.standard)
        XCTAssertEqual(try resolved(Palette.NS.ground, dark: false).redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(try resolved(Palette.NS.frame, dark: true).redComponent, 0.075, accuracy: 0.001)
    }

    func testPersistenceValidatesEachColorWithoutTouchingOtherPreferences() throws {
        let suite = "org.moonbrowser.Moon.colors-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("keep", forKey: "unrelated")
        var colors = ChromeColors.standard; colors.enabled = true
        colors.light.background = "BAD"; colors.dark.text = "123456"; colors.dark.accent = "invalid"
        defaults.set(try JSONEncoder().encode(colors), forKey: ChromeColors.key)
        let loaded = ChromeColors.load(from: defaults)
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.light.background, ChromeColorSet.light.background)
        XCTAssertEqual(loaded.dark.text, "123456")
        XCTAssertNil(loaded.dark.accent)
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
        defaults.set(Data("not JSON".utf8), forKey: ChromeColors.key)
        XCTAssertEqual(ChromeColors.load(from: defaults), .standard)
    }

    func testColorsAreDiscoverableUnderAppearance() throws {
        let item = try XCTUnwrap(SettingsIndex.item("appearance.colors"))
        XCTAssertEqual(item.page, .appearance)
        XCTAssertEqual(item.group, "colors")
        XCTAssertTrue(item.keys.contains(ChromeColors.key))
    }
}

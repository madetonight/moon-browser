import AppKit
import WebKit
import XCTest
@testable import Moon

/// Exercises the real isolated-world DOM path with a deterministic translator.
/// No language download, real profile, or external translation service is used.
@MainActor
final class WebsiteTranslationTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "website-translation-\(getpid())", 1)
        super.setUp()
    }

    func testChangingTargetRestoresBeforeCollectingAndOriginalRemainsExact() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let previous = getenv("MOON_TRANSLATE_FAKE").map { String(cString: $0) }
        setenv("MOON_TRANSLATE_FAKE", "1", 1)
        defer {
            if let previous { setenv("MOON_TRANSLATE_FAKE", previous, 1) }
            else { unsetenv("MOON_TRANSLATE_FAKE") }
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let tab = Moon.Tab(shy: true, configuration: configuration)
        let web = tab.web
        defer { tab.translator?.end(restore: true); web.stopLoading() }
        web.loadHTMLString("""
        <!doctype html><html lang="fr"><head><title>Translation fixture</title></head><body>
        <p id="words">Bonjour à tous, voici une longue phrase en français pour que la page soit bien reconnue.</p>
        <input id="password" type="password" value="synthetic-password">
        <textarea id="draft">Brouillon privé</textarea>
        <div contenteditable="true" id="editor">Texte modifiable privé</div>
        <p translate="no" id="keep">Ne pas traduire</p>
        <span class="google-symbols" id="glyph">personalized_recommendations</span>
        <span class="material-symbols-outlined" id="glyph2">history</span>
        </body></html>
        """, baseURL: URL(string: "https://translation.invalid"))
        try await wait { web.title == "Translation fixture" && !web.isLoading }
        let original = try await web.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertNotNil(PageTranslator.start(tab, to: Locale.Language(identifier: "en")))
        try await wait { tab.translation?.phase == .done || tab.translation?.failed == true }
        XCTAssertEqual(tab.translation?.phase, .done)
        var text = try await web.evaluateJavaScript("document.getElementById('words').textContent") as? String
        XCTAssertTrue(text?.hasPrefix("[fr→en] ") == true, text ?? "missing text")

        // Start another target without awaiting restoration in the caller.
        XCTAssertNotNil(PageTranslator.start(tab, to: Locale.Language(identifier: "de")))
        try await wait { tab.translation?.phase == .done || tab.translation?.failed == true }
        XCTAssertEqual(tab.translation?.phase, .done)
        text = try await web.evaluateJavaScript("document.getElementById('words').textContent") as? String
        XCTAssertTrue(text?.hasPrefix("[fr→de] Bonjour") == true, text ?? "missing text")
        XCTAssertFalse(text?.contains("[fr→en]") == true, "The second pass must not translate already translated text")

        let glyphs = try await web.evaluateJavaScript("[document.getElementById('glyph').textContent, document.getElementById('glyph2').textContent]") as? [String]
        XCTAssertEqual(glyphs, ["personalized_recommendations", "history"], "Icon ligatures must survive website translation unchanged")
        let protected = try await web.evaluateJavaScript("[document.getElementById('password').value, document.getElementById('draft').value, document.getElementById('editor').textContent, document.getElementById('keep').textContent]") as? [String]
        XCTAssertEqual(protected, ["synthetic-password", "Brouillon privé", "Texte modifiable privé", "Ne pas traduire"])
        tab.translator?.end(restore: true)
        await tab.translationRestore?.value
        let restored = try await web.evaluateJavaScript("document.body.innerHTML") as? String
        XCTAssertEqual(restored, original)
        XCTAssertNil(tab.translator)
        XCTAssertNil(tab.translation)
    }

    func testTranslatorAvailabilityExcludesInternalAndExtensionPages() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let tab = Moon.Tab(shy: true, configuration: configuration)
        XCTAssertFalse(tab.canTranslate)
        _ = tab.web
        tab.restore(url: URL(string: "wk-web-extension://synthetic/options.html")!, title: "Extension")
        XCTAssertFalse(tab.canTranslate)
        tab.restore(url: URL(string: "https://translation.invalid")!, title: "Website")
        XCTAssertTrue(tab.canTranslate)
        tab.show(InternalPage(.settings))
        XCTAssertFalse(tab.canTranslate)
    }

    func testDismissClosesTranslatorWithoutClosingThePage() {
        let browser = Browser(record: WindowRecord())
        let active = browser.activeID
        let tabs = browser.tabs.map(\.id)
        browser.translationOpen = true
        XCTAssertTrue(browser.closePanel())
        XCTAssertFalse(browser.translationOpen)
        XCTAssertEqual(browser.activeID, active)
        XCTAssertEqual(browser.tabs.map(\.id), tabs)
        XCTAssertFalse(browser.closePanel())
    }

    func testTranslateCommandRevealsItsAnchorWithoutUnfoldingTheSidebar() throws {
        let browser = Browser(record: WindowRecord())
        let tab = try XCTUnwrap(browser.active)
        _ = tab.web
        tab.restore(url: URL(string: "https://translation.invalid")!, title: "Website")
        browser.folded = true
        browser.peeking = false
        browser.openTranslation()
        XCTAssertTrue(browser.translationOpen)
        XCTAssertTrue(browser.peeking)
        XCTAssertTrue(browser.folded, "The command reveals its anchor without changing the folding preference")
        XCTAssertTrue(browser.closePanel())
        XCTAssertFalse(browser.translationOpen)
    }

    func testUnavailableTranslationDoesNotRevealTheSidebar() {
        let browser = Browser(record: WindowRecord())
        // An explicitly unavailable page; another fixture may have saved a website.
        browser.active?.show(InternalPage(.settings))
        browser.folded = true
        browser.peeking = false
        browser.openTranslation()
        XCTAssertFalse(browser.translationOpen)
        XCTAssertFalse(browser.peeking)
        XCTAssertTrue(browser.folded)
    }

    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !predicate() {
            guard Date() < deadline else { throw NSError(domain: "WebsiteTranslationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Translation fixture timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

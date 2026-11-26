import Foundation
import MoonCore
import XCTest
@testable import Moon

@MainActor
final class MoonCustomizationTests: XCTestCase {
    func testSafariIdentityTracksInstalledWebKit() {
        XCTAssertTrue(Web.userAgentName.hasPrefix("Version/"))
        XCTAssertTrue(Web.userAgentName.hasSuffix("Safari/605.1.15"))
        XCTAssertFalse(Web.userAgentName.contains("Chrome"))
    }

    func testOnlyGeminiIsOfferedAndRemoteKeysStayOnGoogle() {
        XCTAssertEqual(AIProvider.allCases, [.gemini])
        XCTAssertTrue(AIClient.allowed(AIProvider.gemini.base.appendingPathComponent("chat/completions"), for: .gemini))
        for text in ["http://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                     "https://example.com/v1/chat/completions",
                     "https://user:secret@generativelanguage.googleapis.com/v1beta/openai/chat/completions"] {
            XCTAssertFalse(AIClient.allowed(URL(string: text)!, for: .gemini))
        }
        XCTAssertFalse(AIClient.allowed(URL(string: "https://api.openai.com/v1/chat/completions")!, for: .openAI))
    }

    func testNewTabAssistantKeepsPageConsentSeparateAndStopsOnTabChange() throws {
        setenv("MOON_PROBE", "new-tab-assistant-\(getpid())", 1)
        guard Store.settings !== UserDefaults.standard else {
            return XCTFail("The assistant test requires an isolated profile.")
        }
        let browser = Browser(record: WindowRecord())
        let settings = Store.settings
        let generalConsent = "ai.told.general.gemini"
        let pageConsent = "ai.told.gemini"
        let saved = (browser.prefs.ai, browser.prefs.aiProvider,
                     settings.object(forKey: generalConsent), settings.object(forKey: pageConsent))
        let savedKey = AIKeys.key(for: .gemini)
        defer {
            browser.closeAll()
            (browser.prefs.ai, browser.prefs.aiProvider) = (saved.0, saved.1)
            settings.set(saved.2, forKey: generalConsent)
            settings.set(saved.3, forKey: pageConsent)
            if let savedKey { _ = AIKeys.save(savedKey, for: .gemini) }
            else { AIKeys.forget(.gemini) }
        }
        browser.prefs.ai = true
        browser.prefs.aiProvider = .gemini
        settings.removeObject(forKey: generalConsent)
        settings.set(true, forKey: pageConsent)
        _ = AIKeys.save("synthetic-gemini-key", for: .gemini)
        browser.newTab()
        let tab = try XCTUnwrap(browser.active)
        browser.askAnything()
        let assistant = try XCTUnwrap(browser.assisting)
        XCTAssertTrue(assistant.general)
        XCTAssertEqual(assistant.tab, tab.id)
        XCTAssertFalse(assistant.reading)
        assistant.draft = "A question for Gemini"
        assistant.submit()
        XCTAssertNotNil(assistant.notice)
        XCTAssertTrue(assistant.turns.isEmpty)
        browser.show(InternalPage(.settings))
        // Settings may take over the blank tab without changing its id.
        // As a real tab switch, a second tab always releases the assistant.
        browser.newTab()
        XCTAssertNil(browser.assisting)
    }

    func testRetiredCodexPageCannotBeOpened() {
        let tab = Tab()
        let retired = URL(string: "moon://codex")!
        XCTAssertNil(InternalPage(url: retired))
        tab.go(to: retired)
        XCTAssertTrue(tab.isBlank)
        XCTAssertNil(tab.built)
    }

    func testLibraryMigrationKeepsWindowsPinsAndLocalFiles() throws {
        var old = LibraryRecord()
        let space = old.spaces[0].id
        let tab = TabRecord(title: "Notes", url: URL(fileURLWithPath: "/private/tmp/notes.html"), pinned: true, spaceID: space)
        let settings = TabRecord(title: "Settings", spaceID: space)
        var internalTab = settings; internalTab.internalPage = "settings"
        old.windows = [MoonCore.WindowRecord(id: UUID(), tabs: [tab, internalTab], selectedID: internalTab.id, spaceID: space)]
        old.bookmarks = [PageRecord(title: "WebKit", url: URL(string: "https://webkit.org")!)]
        old.history = old.bookmarks
        let input = try JSONEncoder().encode(old)
        let prepared = try MoonMigration.prepare(input)
        let shape = try JSONDecoder().decode(Session.Shape.self, from: XCTUnwrap(prepared.files["session.json"]))
        XCTAssertEqual(shape.tabs.count, 2)
        XCTAssertEqual(shape.tabs[0].url, tab.url?.absoluteString)
        XCTAssertEqual(shape.tabs[0].pinID, tab.id)
        XCTAssertEqual(shape.tabs[1].url, "moon://settings")
        XCTAssertEqual(shape.active, 1)
        XCTAssertEqual(prepared.selectedSpace, Space.firstID)
        let bookmarks = try JSONDecoder().decode([Bookmark].self, from: XCTUnwrap(prepared.files["bookmarks.json"]))
        XCTAssertEqual(bookmarks.first?.title, "WebKit")
    }

    func testMigrationRefusesCorruptLibrary() {
        XCTAssertThrowsError(try MoonMigration.prepare(Data("{broken".utf8)))
    }

    func testIsolatedSpaceKeepsItsWebsiteStoreIdentity() throws {
        var old = LibraryRecord()
        old.spaces[0].isolated = true
        let id = old.spaces[0].id
        let prepared = try MoonMigration.prepare(JSONEncoder().encode(old))
        let spaces = try JSONDecoder().decode([Space].self, from: XCTUnwrap(prepared.files["spaces.json"]))
        XCTAssertTrue(spaces.contains { $0.id == id && $0.sharesSignIns == false })
        XCTAssertTrue(spaces.contains { $0.id == Space.firstID })
    }
}

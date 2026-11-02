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

    func testOnlyLocalOllamaIsAvailable() {
        XCTAssertEqual(AIProvider.allCases, [.ollama])
        XCTAssertTrue(AIClient.allowed(URL(string: "http://127.0.0.1:11434/v1/chat/completions")!, for: .ollama))
        XCTAssertFalse(AIClient.allowed(URL(string: "http://127.0.0.1:9000/v1/chat/completions")!, for: .ollama))
        XCTAssertFalse(AIClient.allowed(URL(string: "https://api.openai.com/v1/chat/completions")!, for: .openAI))
        XCTAssertFalse(AIClient.allowed(URL(string: "https://example.com/v1/chat/completions")!, for: .ollama))
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

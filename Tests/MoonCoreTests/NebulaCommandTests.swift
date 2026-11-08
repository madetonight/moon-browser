import XCTest
@testable import MoonCore

final class NebulaCommandTests: XCTestCase {
    func testNavigationAndPunctuation() {
        XCTAssertEqual(NebulaCommand.parse("  Open a new tab. "), .newTab)
        XCTAssertEqual(NebulaCommand.parse("GO BACK!"), .back)
        XCTAssertEqual(NebulaCommand.parse("scroll down"), .scroll(up: false))
        XCTAssertEqual(NebulaCommand.parse("close this tab"), .closeTab)
    }

    func testSearchPreservesUserText() {
        XCTAssertEqual(NebulaCommand.parse("Search for SwiftUI on macOS"), .search("SwiftUI on macOS"))
        XCTAssertEqual(NebulaCommand.parse("switch to YouTube."), .switchTab("youtube"))
    }

    func testOpenAcceptsOnlyWebDestinations() {
        XCTAssertEqual(NebulaCommand.parse("open example.com"), .open(URL(string: "https://example.com")!))
        for input in ["open javascript:alert(1)", "open file:///etc/passwd",
                      "open https://user:secret@example.com", "open example.com other words",
                      "send this email", "delete my history", "search", "open", ""] {
            XCTAssertNil(NebulaCommand.parse(input), input)
        }
    }

    func testConceptCommandsAndSafeBoundaries() {
        XCTAssertEqual(NebulaCommand.parse("Close all my YouTube tabs."), .closeMatching("youtube"))
        XCTAssertEqual(NebulaCommand.parse("close all of my gmail tabs"), .closeMatching("gmail"))
        XCTAssertEqual(NebulaCommand.parse("Switch to space Work"), .switchSpace("work"))
        XCTAssertEqual(NebulaCommand.parse("summarize this page"), .summarize)
        XCTAssertEqual(NebulaCommand.parse("tidy my tabs"), .tidy)
        XCTAssertNil(NebulaCommand.parse("close all tabs"))
        XCTAssertNil(NebulaCommand.parse("close all my tabs"))
        XCTAssertNil(NebulaCommand.parse("delete all Work tabs and passwords"))
    }

    func testOversizedInputIsRejected() {
        XCTAssertNil(NebulaCommand.parse("search " + String(repeating: "x", count: 2_000)))
    }
}

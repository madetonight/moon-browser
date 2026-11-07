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

    func testOversizedInputIsRejected() {
        XCTAssertNil(NebulaCommand.parse("search " + String(repeating: "x", count: 2_000)))
    }
}

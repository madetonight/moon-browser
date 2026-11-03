import XCTest
@testable import Moon

@MainActor
final class WindowTitleTests: XCTestCase {
    func testWindowIsNamedForItsPage() {
        XCTAssertEqual(WindowTitle.name(page: "Example Domain", private: false), "Example Domain")
        XCTAssertEqual(WindowTitle.name(page: "  Example Domain \n", private: false), "Example Domain")
    }

    func testWindowWithoutAPageTitleIsNamedForTheApp() {
        XCTAssertEqual(WindowTitle.name(page: "", private: false), "Moon")
        XCTAssertEqual(WindowTitle.name(page: "   ", private: false), "Moon")
    }

    func testPrivateTabNeverGivesItsPageAway() {
        XCTAssertEqual(WindowTitle.name(page: "Something personal", private: true), "Private Tab")
    }
}

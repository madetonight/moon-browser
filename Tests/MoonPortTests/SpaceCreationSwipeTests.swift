import AppKit
import XCTest
@testable import Moon

@MainActor
final class SpaceCreationSwipeTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "space-creation-swipe-\(getpid())", 1)
        super.setUp()
    }

    func testRightSwipeOpensCreationWithoutCreatingOrSwitchingASpace() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let sidebar = browser.prefs.sidebar, spaces = browser.prefs.usesSpaces
        defer { browser.prefs.sidebar = sidebar; browser.prefs.usesSpaces = spaces; browser.closeAll() }
        browser.prefs.sidebar = true; browser.prefs.usesSpaces = false
        let original = browser.spaceID, count = browser.spaces.count
        SpaceSwipe.shared.start(for: browser)
        try await Task.sleep(for: .milliseconds(450))
        SpaceSwipe.shared.began()
        XCTAssertTrue(SpaceSwipe.shared.moved(dx: 80, dy: 2))
        XCTAssertTrue(browser.newSpaceSwipe)
        SpaceSwipe.shared.ended()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(browser.makingSpace)
        XCTAssertTrue(browser.prefs.usesSpaces)
        XCTAssertEqual(browser.spaceID, original)
        XCTAssertEqual(browser.spaces.count, count, "A new space still requires its Create button")
    }

    func testShortAndCancelledRightSwipesPreserveTheCurrentSpace() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let sidebar = browser.prefs.sidebar, spaces = browser.prefs.usesSpaces
        defer { browser.prefs.sidebar = sidebar; browser.prefs.usesSpaces = spaces; browser.closeAll() }
        browser.prefs.sidebar = true; browser.prefs.usesSpaces = false
        SpaceSwipe.shared.start(for: browser)
        for (distance, cancelled) in [(20.0, false), (80.0, true)] {
            try await Task.sleep(for: .milliseconds(450))
            SpaceSwipe.shared.began()
            _ = SpaceSwipe.shared.moved(dx: distance, dy: 0)
            SpaceSwipe.shared.ended(cancelled: cancelled)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertFalse(browser.makingSpace)
            XCTAssertFalse(browser.prefs.usesSpaces)
            XCTAssertEqual(browser.spaceSwipe, 0)
        }
    }
}

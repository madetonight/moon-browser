import AppKit
import XCTest
@testable import Moon

@MainActor
final class SpaceCreationSwipeTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "space-creation-swipe-\(getpid())", 1)
        super.setUp()
    }

    private func withBrowser(_ run: (Browser) async throws -> Void) async rethrows {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let prefs = browser.prefs
        let original = (prefs.sidebar, prefs.usesSpaces)
        let saved = Spaces.read(profile: browser.profileID)
        defer {
            browser.closeAll()
            Spaces.write(saved, profile: browser.profileID)
            (prefs.sidebar, prefs.usesSpaces) = original
        }
        prefs.sidebar = true; prefs.usesSpaces = false
        browser.spaces = [browser.space]
        Spaces.write(browser.spaces, profile: browser.profileID)
        SpaceSwipe.shared.start(for: browser)
        try await run(browser)
    }

    private func swipe(_ distance: CGFloat, cancelled: Bool = false) async throws {
        try await Task.sleep(for: .milliseconds(450))
        SpaceSwipe.shared.began()
        _ = SpaceSwipe.shared.moved(dx: distance, dy: 0)
        SpaceSwipe.shared.ended(cancelled: cancelled)
        try await Task.sleep(for: .milliseconds(350))
    }

    func testLeftSwipeCreatesInstantlyAndRightRestoresOriginalTabs() async throws {
        try await withBrowser { browser in
            let home = browser.spaceID, originalTab = browser.activeID
            let originalTabs = browser.tabs.map(\.id)
            try await swipe(-80)
            let created = browser.spaceID
            XCTAssertNotEqual(created, home)
            XCTAssertEqual(browser.spaces.count, 2)
            XCTAssertEqual(browser.space.name, "Space 2")
            XCTAssertEqual(browser.space.sharesSignIns, true)
            XCTAssertEqual(browser.announcement, "Space 2 created")
            XCTAssertTrue(browser.prefs.usesSpaces)
            XCTAssertFalse(browser.makingSpace)
            try await swipe(80)
            XCTAssertEqual(browser.spaceID, home)
            XCTAssertEqual(browser.activeID, originalTab)
            XCTAssertEqual(browser.tabs.map(\.id), originalTabs)
            try await swipe(-80)
            XCTAssertEqual(browser.spaceID, created)
            XCTAssertEqual(browser.spaces.count, 2, "Returning to an existing space must not create another")
            XCTAssertFalse(browser.makingSpace)
        }
    }

    func testRepeatedLeftSwipesCreateSequentialSpacesAndRightReturnsThroughThem() async throws {
        try await withBrowser { browser in
            let home = browser.spaceID
            try await swipe(-80)
            let second = browser.spaceID
            try await swipe(-80)
            XCTAssertEqual(browser.space.name, "Space 3")
            XCTAssertEqual(browser.spaces.count, 3)
            try await swipe(80)
            XCTAssertEqual(browser.spaceID, second)
            try await swipe(80)
            XCTAssertEqual(browser.spaceID, home)
            try await swipe(80)
            XCTAssertEqual(browser.spaceID, home)
            XCTAssertEqual(browser.spaces.count, 3)
            XCTAssertFalse(browser.makingSpace)
        }
    }

    func testShortAndCancelledLeftSwipesPreserveCurrentSpace() async throws {
        try await withBrowser { browser in
            let home = browser.spaceID
            try await swipe(-20)
            try await swipe(-80, cancelled: true)
            XCTAssertEqual(browser.spaceID, home)
            XCTAssertEqual(browser.spaces.count, 1)
            XCTAssertFalse(browser.prefs.usesSpaces)
            XCTAssertFalse(browser.makingSpace)
            XCTAssertEqual(browser.spaceSwipe, 0)
        }
    }

    func testFoldedCreationNeedsNoSetupAndRenamingPreservesIdentity() async throws {
        try await withBrowser { browser in
            browser.folded = true
            browser.askForSpace()
            XCTAssertEqual(browser.space.name, "Space 2")
            XCTAssertFalse(browser.makingSpace)
            let id = browser.spaceID
            browser.renameSpace(id, to: "Reading")
            XCTAssertEqual(browser.spaceID, id)
            XCTAssertEqual(browser.space.name, "Reading")
            XCTAssertEqual(browser.spaces.count, 2)
        }
    }

    func testMoveToNewSpaceCallbackStillRunsWithoutAForm() async throws {
        try await withBrowser { browser in
            var made: Space?
            browser.askForSpace { made = $0 }
            XCTAssertEqual(made?.name, "Space 2")
            XCTAssertEqual(made?.sharesSignIns, true)
            XCTAssertEqual(browser.spaces.count, 2)
            XCTAssertFalse(browser.makingSpace)
            XCTAssertNil(browser.afterSpaceCreated)
        }
    }
}

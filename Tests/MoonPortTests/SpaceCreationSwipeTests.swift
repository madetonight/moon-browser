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

    func testReversingFirstSwipeDoesNotLeaveSidebarOffset() async throws {
        try await withBrowser { browser in
            let home = browser.spaceID
            SpaceSwipe.shared.began()
            XCTAssertTrue(SpaceSwipe.shared.moved(dx: -80, dy: 0))
            XCTAssertEqual(browser.spacePaging.neighbor?.destination, .new)
            XCTAssertTrue(SpaceSwipe.shared.moved(dx: 100, dy: 0))
            SpaceSwipe.shared.ended()
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(browser.spaceID, home)
            XCTAssertEqual(browser.spaces.count, 1)
            XCTAssertEqual(browser.spacePaging.progress, 0)
            XCTAssertNil(browser.spacePaging.neighbor)
        }
    }

    func testIndicatorCanSelectNonAdjacentSpace() async throws {
        try await withBrowser { browser in
            let home = browser.spaceID
            browser.addInstantSpace()
            browser.addInstantSpace()
            let third = browser.spaceID
            browser.switchSpace(to: home)
            SpaceSwipe.shared.select(third, in: browser)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(browser.spaceID, third)
            XCTAssertEqual(browser.spaces.count, 3)
            XCTAssertEqual(browser.spacePaging.progress, 0)
            XCTAssertNil(browser.spacePaging.neighbor)
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

@MainActor
final class SpaceDeletionActionsTests: XCTestCase {
    func testOnlyTargetSpaceIsDeletedAndDefaultIsProtected() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let saved = Spaces.read(profile: browser.profileID)
        let wasEnabled = browser.prefs.usesSpaces
        defer { Ask.testing = nil; browser.closeAll(); Spaces.write(saved, profile: browser.profileID); browser.prefs.usesSpaces = wasEnabled }
        browser.prefs.usesSpaces = true
        browser.spaces = [browser.space]
        Spaces.write(browser.spaces, profile: browser.profileID)
        let home = browser.spaceID
        browser.addSpace(named: "Keep")
        let keep = browser.spaceID
        browser.addSpace(named: "Delete this")
        let remove = browser.spaceID
        browser.switchSpace(to: keep)
        XCTAssertFalse(browser.canDeleteSpace(home))
        Ask.testing = false
        browser.requestDeleteSpace(remove)
        XCTAssertTrue(browser.spaces.contains { $0.id == remove })
        Ask.testing = true
        browser.requestDeleteSpace(remove)
        XCTAssertFalse(browser.spaces.contains { $0.id == remove })
        XCTAssertTrue(browser.spaces.contains { $0.id == keep })
        XCTAssertEqual(browser.spaceID, keep)
        browser.requestDeleteSpace(home)
        XCTAssertTrue(browser.spaces.contains { $0.id == home })
        browser.requestDeleteSpace(remove)
        XCTAssertEqual(browser.spaces.count, 2)
    }

    func testZenCyclicNavigationAndEmptyList() {
        XCTAssertEqual(ZenSpaceNavigation.destination(from: 2, offset: 1, count: 3), 0)
        XCTAssertEqual(ZenSpaceNavigation.destination(from: 0, offset: -1, count: 3), 2)
        XCTAssertEqual(ZenSpaceNavigation.destination(from: 0, offset: 1, count: 0), 0)
    }
}

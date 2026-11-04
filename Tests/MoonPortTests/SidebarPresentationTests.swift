import AppKit
import QuartzCore
import XCTest
@testable import Moon

@MainActor
final class SidebarPresentationTests: XCTestCase {
    func testSidebarSurfaceHasSymmetricMarginsOnEitherSide() {
        for onRight in [false, true] {
            let insets = SidebarSurface.insets(onRight: onRight)
            XCTAssertEqual(insets.leading, insets.trailing)
            XCTAssertEqual(insets.top, insets.bottom)
            XCTAssertEqual(insets.leading, 8)
        }
    }
    private var windows: [NSWindow] = []
    override class func setUp() {
        setenv("MOON_PROBE", "sidebar-presentation-\(getpid())", 1)
        super.setUp()
    }

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        super.tearDown()
    }

    private func bar() -> NSView {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 240, height: 52),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 52))
        view.wantsLayer = true
        window.contentView = view
        window.orderFrontRegardless()
        windows.append(window)
        return view
    }

    func testTwoWindowsCompleteTheirSlidesIndependently() async throws {
        let first = bar(), second = bar()
        Fold.slide(first, off: true, by: 240, reduceMotion: false)
        Fold.slide(second, off: true, by: 240, right: true, reduceMotion: false)
        CATransaction.flush()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while (!first.isHidden || !second.isHidden), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(first.isHidden, "Another window must not cancel this window's completion")
        XCTAssertTrue(second.isHidden)
        XCTAssertNil(first.layer?.animation(forKey: "fold"))
        XCTAssertNil(second.layer?.animation(forKey: "fold"))
    }

    func testReversingOrResettingCannotBeUndoneByAnOldCompletion() async throws {
        let view = bar()
        Fold.slide(view, off: true, by: 240, reduceMotion: false)
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(30))
        Fold.slide(view, off: false, by: 240, reduceMotion: false)
        Fold.reset(view, hidden: false)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(view.isHidden)
        XCTAssertNil(view.layer?.animation(forKey: "fold"))
    }

    func testReducedMotionCancelsAnInFlightSlideImmediately() {
        let view = bar()
        Fold.slide(view, off: true, by: 240, reduceMotion: false)
        XCTAssertNotNil(view.layer?.animation(forKey: "fold"))
        Fold.slide(view, off: true, by: 240, reduceMotion: true)
        XCTAssertTrue(view.isHidden)
        XCTAssertNil(view.layer?.animation(forKey: "fold"))
        Fold.slide(view, off: false, by: 240, reduceMotion: true)
        XCTAssertFalse(view.isHidden)
        XCTAssertNil(view.layer?.animation(forKey: "fold"))
    }
}

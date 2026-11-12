import AppKit
import QuartzCore
import SwiftUI
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

    func testSidebarSlidesItsExistingSurfaceAndKeepsPageHitTestingClear() {
        let surface = SlidingSidebarView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        let window = NSWindow(contentRect: surface.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface
        windows.append(window)
        let originalHost = surface.host
        for right in [false, true] {
            surface.update(content: AnyView(Color.gray), shown: false, width: 240, onRight: right, reduced: false)
            XCTAssertNil(surface.hitTest(NSPoint(x: 5, y: 100)))
            surface.update(content: AnyView(Color.gray), shown: true, width: 240, onRight: right, reduced: false)
            XCTAssertTrue(surface.host === originalHost)
            XCTAssertEqual(surface.host.frame.minX, right ? 660 : 0)
            XCTAssertNotNil(surface.host.layer?.animation(forKey: "sidebarSlide"))
            XCTAssertNil(surface.hitTest(NSPoint(x: 450, y: 100)), "The overlay must not intercept the webpage")
            surface.update(content: AnyView(Color.gray), shown: false, width: 240, onRight: right, reduced: false)
            XCTAssertEqual(surface.host.frame.minX, right ? 900 : -240)
            surface.update(content: AnyView(Color.gray), shown: true, width: 240, onRight: right, reduced: true)
            XCTAssertNil(surface.host.layer?.animation(forKey: "sidebarSlide"))
            XCTAssertEqual(surface.host.frame.minX, right ? 660 : 0)
        }
    }

    func testSidebarResizesWithoutLeavingAStaleSlideOrDetachedSurface() {
        let surface = SlidingSidebarView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        surface.update(content: AnyView(Color.gray), shown: true, width: 240, onRight: true, reduced: false)
        for size in [NSSize(width: 640, height: 420), NSSize(width: 1600, height: 1000)] {
            surface.frame.size = size
            surface.layout()
            XCTAssertEqual(surface.host.frame, NSRect(x: size.width - 240, y: 0, width: 240, height: size.height))
            XCTAssertNil(surface.host.layer?.animation(forKey: "sidebarSlide"))
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

import AppKit
import QuartzCore
import XCTest
@testable import Moon

@MainActor
final class TabHoverHighlightTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "hover-layer-\(getpid())", 1)
        super.setUp()
    }

    func testInitialAndReducedMotionStatesNeverAnimate() {
        _ = NSApplication.shared
        let view = TabHoverLayerView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.update(hovering: false, colour: .gray, radius: 9, reduceMotion: false)
        XCTAssertEqual(view.highlight.opacity, 0)
        XCTAssertNil(view.highlight.animation(forKey: TabHoverLayerView.animationKey))
        view.update(hovering: true, colour: .gray, radius: 9, reduceMotion: false)
        XCTAssertNotNil(view.highlight.animation(forKey: TabHoverLayerView.animationKey))
        view.update(hovering: true, colour: .gray, radius: 9, reduceMotion: true)
        XCTAssertEqual(view.highlight.opacity, 1)
        XCTAssertNil(view.highlight.animation(forKey: TabHoverLayerView.animationKey))
        view.update(hovering: false, colour: .gray, radius: 9, reduceMotion: true)
        XCTAssertEqual(view.highlight.opacity, 0)
        XCTAssertNil(view.highlight.animation(forKey: TabHoverLayerView.animationKey))
    }

    func testUnrelatedUpdatesDoNotRestartAnInFlightFade() throws {
        _ = NSApplication.shared
        let view = TabHoverLayerView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.update(hovering: false, colour: .gray, radius: 9, reduceMotion: false)
        view.update(hovering: true, colour: .gray, radius: 9, reduceMotion: false)
        let fade = try XCTUnwrap(view.highlight.animation(forKey: TabHoverLayerView.animationKey))
        fade.setValue("in flight", forKey: "testMarker")
        view.highlight.add(fade, forKey: TabHoverLayerView.animationKey)
        view.update(hovering: true, colour: .white, radius: 12, reduceMotion: false)
        XCTAssertEqual(view.highlight.animation(forKey: TabHoverLayerView.animationKey)?.value(forKey: "testMarker") as? String, "in flight")
        XCTAssertEqual(view.highlight.cornerRadius, 12)
    }

    func testDecorationNeverInterceptsClicksAndDetachingClearsMotion() {
        _ = NSApplication.shared
        let view = TabHoverLayerView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 30),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.update(hovering: false, colour: .gray, radius: 9, reduceMotion: false)
        view.update(hovering: true, colour: .gray, radius: 9, reduceMotion: false)
        XCTAssertNil(view.hitTest(NSPoint(x: 10, y: 10)))
        window.contentView = nil
        XCTAssertNil(view.highlight.animationKeys())
        window.close()
    }
}

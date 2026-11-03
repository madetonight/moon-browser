import AppKit
import QuartzCore
import SwiftUI
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

    func testVisualFadeRendersIntermediateFramesDespiteRowTransaction() async throws {
        _ = NSApplication.shared
        let state = HoverVisualFixtureState()
        let host = NSHostingView(rootView: HoverVisualFixture(state: state))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 80, height: 30),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(100))
        func brightness() throws -> Double {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let colour = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            return Double(colour.redComponent)
        }
        for over in [true, false] {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { state.over = over }
            var frames: [Double] = []
            // Hosted runners can resume a 10 ms sleep after the entire 160 ms
            // production fade. Slow only this fixture so a busy scheduler can
            // still observe real intermediate pixels in both directions.
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
                frames.append(try brightness())
            }
            XCTAssertTrue(frames.contains { $0 > 0.01 && $0 < 0.99 }, "Entry and exit must visibly fade, not snap despite a passing state-only test; observed \(frames)")
            XCTAssertEqual(try brightness(), over ? 1 : 0, accuracy: 0.02)
        }
    }
}

@MainActor private final class HoverVisualFixtureState: ObservableObject {
    @Published var over = false
}

private struct HoverVisualFixture: View {
    @ObservedObject var state: HoverVisualFixtureState
    var body: some View {
        Color.white.opacity(state.over ? 1 : 0)
            .transaction { $0.animation = $0.animation?.speed(0.1) }
            .modifier(TabHoverFade(hovering: state.over))
            // This is the animated-path fixture. Test it independently of the
            // runner's system accessibility preference; reduced motion is
            // covered explicitly by testInitialAndReducedMotionStatesNeverAnimate.
            .environment(\.accessibilityReduceMotion, false)
            .frame(width: 80, height: 30)
            .background(Color.black)
            .animation(nil, value: state.over)
    }
}

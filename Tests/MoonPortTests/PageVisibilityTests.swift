import AppKit
import WebKit
import XCTest
@testable import Moon

@MainActor
final class PageVisibilityTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "page-visibility-\(getpid())", 1)
        super.setUp()
    }

    private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 640, height: 480),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    func testDetachedPageHidesAndReturnsWithItsDocumentState() async throws {
        let window = window()
        defer { window.contentView = nil; window.close() }
        let web = PageView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: Web.configuration(shy: true))
        defer { web.stopLoading() }
        window.contentView?.addSubview(web)
        XCTAssertFalse(web.isHidden)
        _ = try await web.evaluateJavaScript("window.__retainedState = {draft:'synthetic fixture', position:42}; 1")
        web.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(web.isHidden)
        window.contentView?.addSubview(web)
        XCTAssertFalse(web.isHidden)
        let position = try await web.evaluateJavaScript("window.__retainedState.position") as? Int
        XCTAssertEqual(position, 42, "Changing native visibility must never recreate the document")
    }

    func testWindowTransferDoesNotHideThePresentedPage() async throws {
        let first = window(), second = window()
        defer { first.contentView = nil; second.contentView = nil; first.close(); second.close() }
        let web = PageView(frame: .zero, configuration: Web.configuration(shy: true))
        first.contentView?.addSubview(web)
        web.removeFromSuperview()
        XCTAssertFalse(web.isHidden, "A temporary transfer keeps the existing surface")
        second.contentView?.addSubview(web)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(web.window === second)
        XCTAssertFalse(web.isHidden, "A delayed detach callback cannot hide a floating or split page")
    }
}

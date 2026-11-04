import AppKit
import WebKit
import XCTest
@testable import Moon

@MainActor
final class NavigationPerformanceTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "navigation-performance-\(getpid())", 1)
        super.setUp()
    }
    private func tab() -> Tab {
        _ = NSApplication.shared
        let config = Web.configuration(shy: true)
        let tab = Tab(configuration: config)
        _ = tab.web
        return tab
    }

    func testUnchangedNavigationRetainsInstalledScriptObjects() {
        let tab = tab(); defer { tab.close() }
        let controller = tab.web.configuration.userContentController
        tab.arm(hiding: "", to: URL(string: "https://example.com/one")!)
        let original = controller.userScripts.map(ObjectIdentifier.init)
        XCTAssertFalse(original.isEmpty)
        for i in 0..<100 {
            tab.arm(hiding: "", to: URL(string: "https://example.com/page/\(i)")!)
        }
        XCTAssertEqual(controller.userScripts.map(ObjectIdentifier.init), original,
                       "Ordinary same-site navigation must not reinstall every bridge")
    }

    func testAControllerMutationCannotReuseAnIdenticalSourceInAnotherWorld() {
        let tab = tab(); defer { tab.close() }
        let controller = tab.web.configuration.userContentController
        tab.arm(hiding: "")
        let originals = controller.userScripts
        XCTAssertFalse(originals.isEmpty)
        controller.removeAllUserScripts()
        let replacements = originals.map {
            WKUserScript(source: $0.source, injectionTime: $0.injectionTime,
                         forMainFrameOnly: $0.isForMainFrameOnly, in: .page)
        }
        replacements.forEach(controller.addUserScript)
        let wrong = controller.userScripts.map(ObjectIdentifier.init)
        tab.arm(hiding: "")
        XCTAssertNotEqual(controller.userScripts.map(ObjectIdentifier.init), wrong)
        XCTAssertEqual(controller.userScripts.map(\.source), originals.map(\.source))
    }

    func testChangedOptionsAndSiteStylesInvalidateTheInstallation() {
        let tab = tab(); defer { tab.close() }
        let old = AutoScroll.on; defer { AutoScroll.on = old }
        let controller = tab.web.configuration.userContentController
        AutoScroll.on = false; tab.arm(hiding: "#old{display:none}")
        let before = controller.userScripts.map(ObjectIdentifier.init)
        AutoScroll.on = true; tab.arm(hiding: "#new{display:none}")
        XCTAssertNotEqual(controller.userScripts.map(ObjectIdentifier.init), before)
        XCTAssertTrue(controller.userScripts.contains { $0.source == AutoScroll.script })
        XCTAssertTrue(controller.userScripts.contains { $0.source == Veiling.style("#new{display:none}") })
        XCTAssertFalse(controller.userScripts.contains { $0.source == Veiling.style("#old{display:none}") })
    }

    func testFirstPaintImmediatelyRemovesTheSleepingPreview() throws {
        let tab = tab(); defer { tab.close() }
        let view = tab.web
        guard view.unpainted else { throw XCTSkip("This WebKit does not expose first-paint observation") }
        tab.cover(with: NSImage(size: NSSize(width: 40, height: 40)))
        XCTAssertNotNil(tab.cover)
        view.showFirstFrame()
        XCTAssertNil(tab.cover)
        XCTAssertEqual(view.alphaValue, 1)
    }

    func testANewerNavigationCancelsAPendingRecovery() async throws {
        let tab = tab(); defer { tab.close() }
        let old = URL(string: "data:text/html,<title>old-recovery</title>")!
        let next = URL(string: "data:text/html,<title>new-navigation</title>")!
        tab.setAddressOptimistically(old)
        tab.recoverFromCrash()
        tab.go(to: next)
        try await Task.sleep(for: .milliseconds(1250))
        XCTAssertEqual(tab.web.url, next, "A queued recovery must not replace the user's newer navigation")
    }
}

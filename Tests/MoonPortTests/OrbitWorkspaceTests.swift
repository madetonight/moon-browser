import AppKit
import WebKit
import XCTest
@testable import Moon

@MainActor
final class OrbitWorkspaceTests: XCTestCase {
    func testSummaryBoundsStayInsideNarrowShortAndWideWindows() {
        for size in [CGSize(width: 200, height: 150), CGSize(width: 640, height: 420),
                     CGSize(width: 1180, height: 780)] {
            for sidebarWidth in [0.0, 48.0, 220.0, 480.0] {
                for onRight in [false, true] {
                    let bounds = OrbitSummaryLayout.available(in: size, sidebarWidth: sidebarWidth, onRight: onRight)
                    XCTAssertTrue(CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10).contains(bounds))
                    XCTAssertGreaterThan(bounds.width, 0)
                    XCTAssertGreaterThan(bounds.height, 0)
                }
            }
        }
    }

    func testCloseFrontDismissesOrbitSummaryAndKeepsItsTab() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let orbit = browser.show(InternalPage(.orbit))
        browser.orbitOpen = true
        browser.closeFront()
        XCTAssertFalse(browser.orbitOpen)
        XCTAssertEqual(browser.activeID, orbit.id)
    }

    func testOrbitOpensAndReusesAnInternalTabWithoutCreatingAWindow() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let original = Tab()
        original.restore(url: try XCTUnwrap(URL(string: "about:blank#orbit-test")), title: "Original tab")
        browser.receive(original)
        let windows = NSApp.windows.map(ObjectIdentifier.init)
        let address = try XCTUnwrap(URL(string: "moon://orbit"))
        let page = try XCTUnwrap(InternalPage(url: address))

        let orbit = browser.show(page)
        XCTAssertEqual(browser.activeID, orbit.id)
        XCTAssertEqual(orbit.page?.url, address)
        XCTAssertNil(orbit.built)
        browser.select(original)
        XCTAssertTrue(browser.show(page) === orbit)
        XCTAssertTrue(browser.tabs.contains { $0 === original })
        XCTAssertEqual(NSApp.windows.map(ObjectIdentifier.init), windows)
    }

    func testLocalOnlyRulesCompileInWebKitBeforeLoadingTheWorkspace() async throws {
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: "moon-orbit-rule-regression", encodedContentRuleList: OrbitEngineWebView.networkRules) { list, error in
                if let error { continuation.resume(throwing: error) }
                else if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: NSError(domain: "OrbitRules", code: 1)) }
            }
        }
        XCTAssertEqual(list.identifier, "moon-orbit-rule-regression")
        try await store.removeContentRuleList(forIdentifier: list.identifier)
    }
}

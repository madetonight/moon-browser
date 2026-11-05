import AppKit
import WebKit
import XCTest
@testable import Moon

@MainActor
final class OrbitWorkspaceTests: XCTestCase {
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

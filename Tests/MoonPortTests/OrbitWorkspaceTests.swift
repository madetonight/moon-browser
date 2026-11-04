import WebKit
import XCTest
@testable import Moon

@MainActor
final class OrbitWorkspaceTests: XCTestCase {
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

import Foundation
import XCTest
@testable import MoonCore

final class CodexPolicyTests: XCTestCase {
    func testBrowserToolsBypassCodeModeWithoutEnablingExecutionHosts() {
        XCTAssertTrue(CodexPolicy.configuration.contains("direct_only_tool_namespaces = [\"moon\"]"))
        for feature in ["shell_tool", "unified_exec", "js_repl", "code_mode_host", "apps", "plugins"] {
            XCTAssertTrue(CodexPolicy.configuration.contains("\(feature) = false"))
        }
        XCTAssertTrue(CodexPolicy.configuration.contains("enabled = false"))
    }
    func testOnlyAuthenticatedLocalTransportEndpointsAreEligible() {
        XCTAssertTrue(CodexPolicy.endpoint(URL(string: "ws://127.0.0.1:49152")!))
        for value in ["ws://localhost:49152", "ws://0.0.0.0:49152", "ws://example.com:49152", "ws://127.0.0.1:49152/?token=secret", "ws://user:pass@127.0.0.1:49152", "http://127.0.0.1:49152"] {
            XCTAssertFalse(CodexPolicy.endpoint(URL(string: value)!), value)
        }
    }
    func testWebToolsExcludeNativeSchemesAndEmbeddedCredentials() {
        XCTAssertNotNil(CodexPolicy.webURL("https://example.com/page"))
        for value in ["file:///etc/passwd", "moon://passwords", "javascript:alert(1)", "https://user:secret@example.com", "data:text/html,hello"] {
            XCTAssertNil(CodexPolicy.webURL(value), value)
        }
        XCTAssertFalse(CodexPolicy.tools.contains("shell"))
        XCTAssertFalse(CodexPolicy.tools.contains("evaluate_javascript"))
    }
    func testProtectedFieldsAndOriginBoundaries() {
        for (type, autocomplete) in [("password", ""), ("text", "one-time-code"), ("text", "section-card cc-number"), ("file", "")] {
            XCTAssertTrue(CodexPolicy.protectedField(type: type, autocomplete: autocomplete))
        }
        XCTAssertFalse(CodexPolicy.protectedField(type: "text", autocomplete: "name"))
        XCTAssertEqual(CodexPolicy.origin(URL(string: "https://EXAMPLE.com/a")!), CodexPolicy.origin(URL(string: "https://example.com:443/b")!))
        XCTAssertNotEqual(CodexPolicy.origin(URL(string: "https://example.com")!), CodexPolicy.origin(URL(string: "http://example.com")!))
        XCTAssertTrue(CodexPolicy.requiresHandoff("Pay now"))
        XCTAssertFalse(CodexPolicy.requiresHandoff("View payment history"))
    }
}

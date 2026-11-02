import AppKit
import LocalAuthentication
import XCTest
@testable import Moon

@MainActor final class SecurityHardeningTests: XCTestCase {
    private final class Authentication: LAContext {
        let available: Bool
        let accepted: Bool
        init(available: Bool, accepted: Bool) { self.available = available; self.accepted = accepted; super.init() }
        override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool { available }
        override func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
            reply(accepted, nil)
        }
    }
    func testAuthenticationUnavailableAndDeniedDoNotAuthorize() async {
        let saved = Ask.testing
        Ask.testing = nil
        defer { Ask.testing = saved }
        for (available, accepted, expected) in [(false, true, false), (true, false, false), (true, true, true)] {
            let answered = expectation(description: "authentication result")
            Vault.prove("synthetic test", context: Authentication(available: available, accepted: accepted)) { actual in
                XCTAssertEqual(actual, expected)
                answered.fulfill()
            }
            await fulfillment(of: [answered], timeout: 2)
        }
    }
    func testUpdateConfigurationRejectsDowngradedOrMissingTrust() {
        let valid: [String: Any] = ["SUFeedURL": "https://example.test/appcast.xml",
            "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(), "MoonUpdateFeedReady": true,
            "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true, "SUSignedFeedFailureExpirationInterval": 0]
        XCTAssertNil(Updater.configurationProblem(valid))
        for (key, value) in [("SUFeedURL", "http://example.test/feed" as Any),
                             ("SUPublicEDKey", "not a key" as Any), ("MoonUpdateFeedReady", false as Any),
                             ("SURequireSignedFeed", false as Any), ("SUVerifyUpdateBeforeExtraction", false as Any),
                             ("SUSignedFeedFailureExpirationInterval", 60 as Any)] {
            var altered = valid; altered[key] = value
            XCTAssertNotNil(Updater.configurationProblem(altered), key)
        }
    }
}

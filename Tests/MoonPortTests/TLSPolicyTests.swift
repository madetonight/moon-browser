import AppKit
import Security
import WebKit
import XCTest
@testable import Moon

@MainActor final class TLSPolicyTests: XCTestCase {
    private final class Space: URLProtectionSpace {
        var fixtureTrust: SecTrust?
        override var serverTrust: SecTrust? { fixtureTrust }
    }
    private final class Sender: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
    }
    func testUntrustedCertificatesNeverReceiveAnAppTrustOverride() throws {
        _ = NSApplication.shared
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, Data(base64Encoded: "MIICpDCCAYwCCQDP0rH2ReT1bjANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwHhcNMjYxMDI3MjI1OTEyWhcNMjYxMDI5MjI1OTEyWjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDQjeuI4IpObPEt1AlOwYO4yxt1vtYP0Omh+bt3iriYDd97g6p611XOxTBzvaXLiXZvyaZXKCsvU0eZ55cuiHwiYBelDl/rod+8amUJnnUB38smUXjYFtB3w4bido4/FMTSlopN0/50XCILjUjB+c6muhGLsXm+covH4iuSYpmVJf48N7R9B7cURgK4+qbxRt/ItqhVXYuLYTNpgSacXaI8+M9ihHFrrOZGIcAIU2qIBia+OKvm0nxYyYp+94qkOLGyeHfvbDzLvd8XfKcUBycjucpLY6Yeuhzu9r64K6P8LowQt9Z75/tIJbQrIEJTY5lbjwHrV56kcBylDAvhO2dxAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAEdxIEC9MZ75pbxXiF9fZi6JLsb6nfj8yAqtzCKDJ7LucROlzGtykBxOddp/b1T7hQcBlcWq5KO9Ugi0Tr60u8Vkq0SlWhGWTQBkjstbR1dTM0Y0ti5768RA7QgMK44m8sIYDmtx1AnaEHZsdgkY4YC0s/kbYHs0G6OzTVmPNEzpBwdsKFqt+ni7rMFI5gWP6FID2OZIJE2RrMo2T4XGKi8SdniDOSawJOpeUk7JKDQJLGLWrdXAwN9Fu14nVx8ephtcn+HmXp3cU9loQmuEE+CT2HnwH2FPJOIgIvlo1r+mU4p77i0gN6xT3itWBr27v37jQFW0PL7pXlVWuYRYsKo=")! as CFData))
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        for host in ["localhost", "127.0.0.1", "::1", "example.test", "127.0.0.1.attacker.test"] {
            var trust: SecTrust?
            XCTAssertEqual(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, host as CFString), &trust), errSecSuccess)
            let space = Space(host: host, port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
            space.fixtureTrust = trust
            let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil,
                previousFailureCount: 0, failureResponse: nil, error: nil, sender: Sender())
            let web = WKWebView(frame: .zero, configuration: Web.configuration(shy: true))
            var called = false
            browser.webView(web, didReceive: challenge) { disposition, credential in
                called = true
                XCTAssertEqual(disposition, .performDefaultHandling, host)
                XCTAssertNil(credential, host)
            }
            XCTAssertTrue(called)
        }
    }
}

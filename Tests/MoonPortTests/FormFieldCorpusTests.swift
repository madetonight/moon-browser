import AppKit
import Foundation
import WebKit
import XCTest
@testable import Moon

/// Which boxes saved accounts are offered in (#631), on real-world forms kept
/// in Tests/FieldFixtures: Forms.script's judge, run in Moon's own world as
/// a tab runs it, on each fixture at the address it was taken from. No
/// keychain, no window.
@MainActor
final class FormFieldCorpusTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("FieldFixtures")

    private struct Fixture {
        let file: String
        let url: URL
        let expect: String
        let name: Bool?
        let html: String
    }

    private var holding: [NSObject] = []

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
    }

    override func tearDown() async throws {
        holding = []
        try await super.tearDown()
    }

    func testEveryFixtureIsOfferedWhatItShouldBe() async throws {
        let all = try Self.corpus()
        XCTAssertGreaterThanOrEqual(all.count, 13, "the corpus is there")
        for fixture in all {
            let verdict = try await judge(fixture)
            let got = verdict == nil ? "none" : (verdict?["wide"] as? Bool == true ? "wide" : "exact")
            XCTAssertEqual(got, fixture.expect, "\(fixture.file): offered \(got), expected \(fixture.expect)")
            if let name = fixture.name, verdict != nil {
                XCTAssertEqual(verdict?["name"] as? Bool, name, "\(fixture.file): a pick puts in the name alone?")
            }
        }
    }

    /// The fixtures the brief names are all there, so the corpus can't
    /// quietly shrink.
    func testTheCorpusCoversTheNamedSites() throws {
        let files = Set(try Self.corpus().map(\.file))
        for needed in ["gcloud-new-project", "github-new-repo", "notion-page-title", "slack-message",
                       "gmail-compose-to", "amazon-search", "urssaf-login", "google-identifier",
                       "impots-identifier", "norma-password-only", "okta-username", "newsletter-signup",
                       "checkout-email"] {
            XCTAssertTrue(files.contains(needed), "\(needed).html is in the corpus")
        }
    }

    /// The scope: a real sign-in box gets the site's accounts, its other
    /// hosts' too; a box that only might be one, this host's alone. Gmail's
    /// account, kept for accounts.google.com, never reaches a box on
    /// console.cloud.google.com that isn't clearly a sign-in's.
    func testOnlyARealSignInReachesTheSitesOtherHosts() {
        let console = "console.cloud.google.com"
        XCTAssertTrue(Vault.belongs("accounts.google.com", to: console, wide: true))
        XCTAssertFalse(Vault.belongs("accounts.google.com", to: console, wide: false))
        XCTAssertTrue(Vault.belongs(console, to: console, wide: false))
        XCTAssertFalse(Vault.belongs("google.co.uk", to: console, wide: true), "another site is never offered")
        XCTAssertTrue(ApplePasswords.belongs(["https://accounts.google.com"], to: console, wide: true))
        XCTAssertFalse(ApplePasswords.belongs(["https://accounts.google.com"], to: console, wide: false))
        XCTAssertTrue(ApplePasswords.belongs(["https://www.console.cloud.google.com/"], to: console, wide: false))
    }

    // MARK: -

    func testMessageUpdatesAvoidPasswordScansAndDynamicSignInStillWorks() async throws {
        _ = try await judge(Fixture(file: "message-mutations", url: URL(string: "https://example.invalid/")!,
                                   expect: "none", name: nil,
                                   html: "<p id='message' data-probe tabindex='0'>Inbox</p><div id='rows'></div>"))
        let web = try XCTUnwrap(holding.compactMap { $0 as? WKWebView }.last)
        let relay = try XCTUnwrap(holding.compactMap { $0 as? Quiet }.last)
        // Let the two initial delayed form checks finish before measuring
        // mutation-driven work, as a settled inbox would.
        try await Task.sleep(for: .milliseconds(2400))
        _ = try await call(web, """
        window.passwordScans = 0;
        const query = document.querySelectorAll.bind(document);
        document.querySelectorAll = function (selector) {
          if (selector === 'input[type="password"]') window.passwordScans++;
          return query(selector);
        };
        for (let i=0; i<100; i++) document.getElementById('message').textContent = 'Message ' + i;
        document.getElementById('rows').innerHTML = '<div>Updated row</div>'.repeat(200);
        return true;
        """)
        try await Task.sleep(for: .milliseconds(400))
        let scans = try await call(web, "return window.passwordScans;") as? Int
        XCTAssertEqual(scans, 0, "Message and inbox mutations must not trigger a whole-document password scan")
        _ = try await call(web, """
        const form = document.createElement('form'); form.id = 'dynamic-login';
        form.innerHTML = '<input autocomplete="username"><input type="password">';
        document.body.append(form); return true;
        """)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(relay.kinds.contains("form"), "A dynamically inserted login must still be detected")
        _ = try await call(web, "document.getElementById('dynamic-login').remove(); return true;")
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertTrue(relay.kinds.contains("settled"), "Removing the login must still complete the sign-in lifecycle")
    }

    private static func corpus() throws -> [Fixture] {
        let names = try FileManager.default.contentsOfDirectory(atPath: fixtures.path)
            .filter { $0.hasSuffix(".html") }.sorted()
        return try names.map { name in
            let html = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
            let head = html.prefix(while: { $0 != "\n" })
            func field(_ key: String) -> String? {
                guard let range = head.range(of: key + ": ") else { return nil }
                return head[range.upperBound...].split(separator: " ").first.map(String.init)
            }
            guard let address = field("url"), let url = URL(string: address), let expect = field("expect") else {
                throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name): no url/expect line"])
            }
            return Fixture(file: String(name.dropLast(5)), url: url, expect: expect,
                           name: field("name").map { $0 == "true" }, html: html)
        }
    }

    private func judge(_ fixture: Fixture) async throws -> [String: Any]? {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let quiet = Quiet()
        configuration.userContentController.add(quiet, contentWorld: Web.world, name: FormRelay.name)
        configuration.userContentController.addUserScript(
            WKUserScript(source: FormRelay.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Web.world))
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        let loaded = Loaded()
        holding += [loaded, quiet, web]
        web.navigationDelegate = loaded
        // Nothing leaves the Mac: the fixture's address is only its base, and
        // every load but the fixture itself is refused.
        web.loadHTMLString(fixture.html, baseURL: fixture.url)
        try await loaded.wait()
        let answer = try await call(web, """
        var el = document.querySelector('[data-probe]');
        if (!el) return 'missing';
        try { el.focus(); } catch (e) {}
        return window.__officeForms ? window.__officeForms.verdict(el) : 'no script';
        """)
        if let text = answer as? String { XCTFail("\(fixture.file): \(text)") }
        return answer as? [String: Any]
    }

    private func call(_ web: WKWebView, _ body: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(body, arguments: [:], in: nil, in: Web.world) { (result: Result<Any, Error>) in
                continuation.resume(with: result.map { $0 is NSNull ? nil : $0 })
            }
        }
    }

    private final class Quiet: NSObject, WKScriptMessageHandler {
        var kinds: [String] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any], let kind = body["kind"] as? String { kinds.append(kind) }
        }
    }

    private final class Loaded: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?
        private var done = false

        func wait() async throws {
            if done { return }
            try await withCheckedThrowingContinuation { self.continuation = $0 }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.scheme == "about" || !done ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            done = true
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            done = true
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            done = true
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

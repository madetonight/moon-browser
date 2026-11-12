import AppKit
import Foundation
import SwiftUI
import WebKit
import XCTest
@testable import Moon

@MainActor
final class CodexIntegrationTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "codex-integration-\(getpid())", 1)
        super.setUp()
    }
    func testCodexBrowserNamespaceStaysDirectAndGeminiKeepsFunctionSpecs() throws {
        let namespace = try XCTUnwrap(CodexBrowserTools.codexSpecs.first)
        XCTAssertEqual(namespace["name"] as? String, "moon")
        XCTAssertEqual(namespace["type"] as? String, "namespace")
        let tools = try XCTUnwrap(namespace["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }.sorted(), CodexBrowserTools.specs.compactMap { $0["name"] as? String }.sorted())
        XCTAssertTrue(tools.allSatisfy { $0["type"] as? String == "function" })
    }
    func testReadingWaitsBrieflyForBackgroundContentWithoutAModelRetry() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let tab = Tab(configuration: Web.configuration())
        browser.insert(tab, at: 0)
        let web = tab.web
        let address = URL(string: "https://agent.invalid/")!
        web.loadHTMLString("<html><head><title>Delayed content</title></head><body><script>setTimeout(()=>{document.body.innerHTML='<p>Readable content appeared after the document finished loading.</p>'},180)</script></body></html>", baseURL: address)
        try await wait { web.title == "Delayed content" && !web.isLoading }
        tab.restore(url: address, title: "Delayed content")
        let session = CodexSession(browser: browser, tab: UUID(), provider: .codex)
        defer { session.close() }
        session.share(tab, origin: address)
        let read = try await CodexBrowserTools.perform("moon_read", ["tab": tab.id.uuidString], session: session)
        XCTAssertTrue((read["untrusted_page_text"] as? String)?.contains("Readable content appeared") == true)
    }
    func testReadingReadyTextDoesNotWaitForPendingImages() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let configuration = Web.configuration()
        let pending = PendingAgentImage()
        configuration.setURLSchemeHandler(pending, forURLScheme: "moon-pending")
        let tab = Tab(configuration: configuration)
        browser.insert(tab, at: 0)
        let web = tab.web
        let address = URL(string: "https://agent.invalid/")!
        web.loadHTMLString("<html><head><title>Ready text</title></head><body><p>This page has readable content while its image is still loading.</p><img src='moon-pending://asset/image'></body></html>", baseURL: address)
        try await wait { pending.started }
        for _ in 0..<50 {
            if (try? await web.evaluateJavaScript("document.readyState")) as? String == "interactive" { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertTrue(web.isLoading)
        let readyState = try await web.evaluateJavaScript("document.readyState") as? String
        XCTAssertEqual(readyState, "interactive")
        tab.restore(url: address, title: "Ready text")
        let session = CodexSession(browser: browser, tab: UUID(), provider: .codex)
        defer { session.close() }
        session.share(tab, origin: address)
        let start = Date()
        let read = try await CodexBrowserTools.perform("moon_read", ["tab": tab.id.uuidString], session: session)
        XCTAssertTrue((read["untrusted_page_text"] as? String)?.contains("readable content") == true)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5, "Reading must not wait four seconds for unrelated media")
    }
    func testActionHistoryShowsRealOutcomesWithoutFieldValues() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let session = CodexSession(browser: browser, tab: UUID(), provider: .codex)
        defer { session.close() }
        session.messages = [.init(user: true, text: "Check my tabs"), .init(user: false, text: "")]
        _ = try await CodexBrowserTools.perform("moon_tabs", [:], session: session)
        XCTAssertEqual(session.conversationTitle, "Check my tabs")
        XCTAssertEqual(session.messages.last?.steps.map(\.title), ["Checking shared tabs"])
        XCTAssertEqual(session.messages.last?.steps.map(\.state), ["Done"])
        do {
            _ = try await CodexBrowserTools.perform("moon_fill", ["tab": UUID().uuidString, "text": "synthetic-private-value"], session: session)
            XCTFail("Unshared tab must remain inaccessible")
        } catch { }
        XCTAssertEqual(session.messages.last?.steps.last?.state, "Not completed")
        XCTAssertFalse(session.messages.last!.steps.contains { $0.title.contains("synthetic-private-value") })
    }
    func testOnlyCodexAndGeminiAreOfferedAndCodexOpensFreshNativeTabs() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        XCTAssertEqual(AIProvider.allCases, [.codex, .gemini])
        let first = browser.openCodex(), second = browser.openCodex()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.page?.kind, .codex)
        XCTAssertEqual(second.page?.kind, .codex)
        XCTAssertNil(first.built)
        XCTAssertNil(second.built)
        XCTAssertEqual(browser.activeID, second.id)
    }
    func testSharingExpiresOnOriginChangeAndNeverIncludesPrivateOrInternalTabs() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let page = Tab(configuration: Web.configuration())
        page.restore(url: URL(string: "https://one.invalid/a")!, title: "One")
        browser.insert(page, at: 0)
        let session = CodexSession(browser: browser, tab: UUID(), provider: .codex)
        defer { session.close() }
        XCTAssertNil(session.tab(page.id.uuidString))
        session.share(page, origin: try XCTUnwrap(page.pageAddress))
        XCTAssertTrue(session.tab(page.id.uuidString) === page)
        page.restore(url: URL(string: "https://two.invalid/")!, title: "Two")
        XCTAssertNil(session.tab(page.id.uuidString))
        let secret = Tab(shy: true, configuration: Web.configuration(shy: true))
        secret.restore(url: URL(string: "https://private.invalid")!, title: "Private")
        XCTAssertFalse(CodexSession.canShare(secret))
        page.show(InternalPage(.passwords))
        XCTAssertFalse(CodexSession.canShare(page))
    }
    func testGeminiUsesTheSameNativeApprovalBeforeFillingAField() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let tab = Tab(configuration: Web.configuration())
        browser.insert(tab, at: 0)
        let web = tab.web
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 640, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = web; window.orderFrontRegardless()
        web.loadHTMLString("<html><head><title>Agent fixture</title></head><body><input aria-label='Message' id='message'><input id='secret' aria-label='Secret' type='password' value='synthetic-password'><input id='card' autocomplete='cc-number' value='synthetic-card'></body></html>", baseURL: URL(string: "https://agent.invalid"))
        try await wait { web.title == "Agent fixture" && !web.isLoading }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexFixtureProtocol.self]
        CodexFixtureProtocol.setTab(tab.id.uuidString)
        _ = AIKeys.save("synthetic-gemini-key", for: .gemini)
        let client = GeminiBrowserAgent(network: URLSession(configuration: configuration))
        let session = CodexSession(browser: browser, tab: UUID(), provider: .gemini, gemini: client)
        defer {
            session.close(); AIKeys.forget(.gemini); window.contentView = nil; window.close(); browser.closeAll()
        }
        session.share(tab, origin: try XCTUnwrap(tab.pageAddress))
        session.connect()
        try await wait { session.connected && session.signedIn }
        session.draft = "Fill the Message field"
        session.send()
        try await wait { session.approval != nil }
        let before = try await web.evaluateJavaScript("document.getElementById('message').value") as? String
        XCTAssertEqual(before, "", "A provider cannot change a field before approval")
        session.resolveApproval(true)
        try await wait { !session.busy }
        let after = try await web.evaluateJavaScript("document.getElementById('message').value") as? String
        XCTAssertEqual(after, "<b>literal text</b>")
        let secret = try await web.evaluateJavaScript("document.getElementById('secret').value") as? String
        XCTAssertEqual(secret, "synthetic-password")
        XCTAssertFalse(CodexFixtureProtocol.sawProtectedValue())
    }
    func testNebulaIsAStripRatherThanALargePanel() async throws {
        _ = NSApplication.shared
        let prefs = Shared.prefs, glass = prefs.liquidGlass
        prefs.liquidGlass = false
        defer { prefs.liquidGlass = glass }
        let host = NSHostingView(rootView: NebulaPanel(nebula: Nebula()).frame(width: 360))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 360, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertLessThanOrEqual(host.fittingSize.height, 64)
    }
    private func wait(_ condition: () -> Bool) async throws {
        let limit = Date().addingTimeInterval(12)
        while !condition() {
            guard Date() < limit else { throw NSError(domain: "CodexIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for fixture"]) }
            try await Task.sleep(for: .milliseconds(30))
        }
    }
}

/// The lock serializes fixture state; this never contacts the real API.
private final class CodexFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var tab = ""
    private static var protectedValue = false
    static func setTab(_ id: String) { lock.lock(); defer { lock.unlock() }; tab = id; protectedValue = false }
    static func sawProtectedValue() -> Bool { lock.lock(); defer { lock.unlock() }; return protectedValue }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "generativelanguage.googleapis.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let id = Self.tab
        Self.lock.unlock()
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(contentsOf: buffer.prefix(n)) }
        }
        let text = String(decoding: body, as: UTF8.self)
        if text.contains("synthetic-password") || text.contains("synthetic-card") {
            Self.lock.lock(); Self.protectedValue = true; Self.lock.unlock()
        }
        let data: [String: Any]
        if request.url?.path.hasSuffix("/models") == true {
            data = ["models": [["name": "models/gemini-fixture", "supportedGenerationMethods": ["generateContent"]]]]
        } else {
            let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let contents = json?["contents"] as? [[String: Any]] ?? []
            let last = (contents.last?["parts"] as? [[String: Any]])?.first
            let response = last?["functionResponse"] as? [String: Any]
            let parts: [[String: Any]]
            if response?["name"] as? String == "moon_inspect" {
                let result = response?["response"] as? [String: Any]
                let field = (result?["elements"] as? [[String: Any]])?.first { $0["label"] as? String == "Message" }
                parts = [["functionCall": ["name": "moon_fill", "id": "fill", "args": ["tab": id, "element": field?["reference"] as? String ?? "missing", "text": "<b>literal text</b>"]]]]
            } else if response?["name"] as? String == "moon_fill" {
                parts = [["text": "Done."]]
            } else { parts = [["functionCall": ["name": "moon_inspect", "id": "inspect", "args": ["tab": id]]]] }
            data = ["candidates": [["content": ["role": "model", "parts": parts]]]]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: data))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class PendingAgentImage: NSObject, WKURLSchemeHandler {
    private(set) var started = false
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) { started = true }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) { }
}

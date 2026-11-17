import AppKit
import WebKit
import XCTest
@testable import Moon

@MainActor
final class GhostBrowsingTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "ghost-tests-\(getpid())", 1)
        super.setUp()
    }

    func testGhostWindowAndEveryNewWebsiteUseTemporaryStoresAndNoSavedSession() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), ghostWindow: true)
        defer { browser.closeAll() }
        XCTAssertFalse(browser.usesFiles)
        XCTAssertTrue(browser.tabs.allSatisfy(\.shy))
        let firstStore = try XCTUnwrap(browser.active?.store)
        XCTAssertFalse(firstStore.isPersistent)
        let page = browser.open(URL(string: "https://example.test/private")!, foreground: true)
        XCTAssertTrue(page.shy)
        XCTAssertTrue(page.store === firstStore)
        browser.peek(URL(string: "https://example.test/preview")!, from: page)
        XCTAssertTrue(browser.peekTab?.shy == true)
        XCTAssertTrue(browser.peekTab?.store === firstStore)
        browser.closePeek()
        browser.newTab()
        XCTAssertTrue(browser.active?.shy == true)
        XCTAssertTrue(browser.active?.store === firstStore)
        browser.restoreSession()
        XCTAssertTrue(browser.tabs.allSatisfy(\.shy))
        let pins = Pins.defs(browser.spaceID)
        browser.writeSession(now: true)
        XCTAssertEqual(Pins.defs(browser.spaceID), pins)
        XCTAssertTrue(browser.allRows().values.allSatisfy { $0.tabs.isEmpty })
        browser.takeFiles()
        XCTAssertFalse(browser.usesFiles)
    }

    func testNormalTabTransferredIntoGhostGetsANewPrivateStore() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(), ghostWindow: true)
        defer { browser.closeAll() }
        let normal = Tab(configuration: Web.configuration())
        normal.restore(url: URL(string: "https://example.test/transfer")!, title: "Normal")
        let id = normal.id
        browser.receive(normal)
        XCTAssertFalse(browser.tabs.contains { $0.id == id })
        XCTAssertTrue(browser.active?.shy == true)
        XCTAssertFalse(browser.active?.store.isPersistent ?? true)
    }

    func testGhostCloseIsNotRecoverableAndPanicPreservesNormalTabs() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        Browsers.register(browser)
        defer { Browsers.discard(browser) }
        let normal = browser.open(URL(string: "https://example.test/normal")!, foreground: true)
        browser.newShyTab()
        let privateID = browser.activeID
        browser.parked[UUID()] = Parked(tabs: [Tab(shy: true)], active: nil)
        Browsers.ghostPanic()
        XCTAssertTrue(browser.tabs.contains { $0.id == normal.id })
        XCTAssertFalse(browser.tabs.contains { $0.id == privateID })
        XCTAssertFalse(browser.parkedTabs.contains(where: \.shy))
        XCTAssertTrue(browser.ghosts.isEmpty)
    }

    func testInsightsAllowWebLinksButRefuseCredentialsAndExecutableSchemes() {
        for url in ["https://example.test/page", "http://example.test/"] {
            XCTAssertTrue(LinkInsight.allowed(URL(string: url)!))
        }
        for url in ["file:///etc/passwd", "javascript:alert(1)", "https://user:secret@example.test", "moon://settings"] {
            XCTAssertFalse(LinkInsight.allowed(URL(string: url)!))
        }
    }

    func testGhostCookiesDoNotReachNormalBrowsingOrANewGhostWindow() async throws {
        let browser = Browser(record: WindowRecord(), ghostWindow: true)
        let store = try XCTUnwrap(browser.ghostStore)
        let name = "ghost-fixture-" + UUID().uuidString
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.test", .path: "/", .name: name, .value: "local-test"]))
        await store.httpCookieStore.setCookie(cookie)
        let privateCookies = await store.httpCookieStore.allCookies()
        XCTAssertTrue(privateCookies.contains { $0.name == name })
        let normalCookies = await Store.websites.httpCookieStore.allCookies()
        XCTAssertFalse(normalCookies.contains { $0.name == name })
        browser.closeAll()
        let next = Browser(record: WindowRecord(), ghostWindow: true)
        defer { next.closeAll() }
        let nextStore = try XCTUnwrap(next.ghostStore)
        let nextCookies = await nextStore.httpCookieStore.allCookies()
        XCTAssertFalse(nextCookies.contains { $0.name == name })
    }

    func testLinkInsightReadsMetadataWithoutRunningThePageScript() async throws {
        let server = try LocalPageServer(["/insight": .init(type: "text/html", body: """
        <!doctype html><meta charset="utf-8"><title>A useful article</title>
        <meta name="description" content="A concise description supplied by the website.">
        <script>document.querySelector('meta[name=description]').content='Page JavaScript ran';</script>
        <p>This is fixture content, never personal browser data.</p>
        """)])
        defer { server.stop() }
        let insight = LinkInsight(url: server.url("/insight"), anchor: .zero)
        await insight.load()
        XCTAssertEqual(insight.title, "A useful article")
        XCTAssertEqual(insight.summary, "A concise description supplied by the website.")
    }
}

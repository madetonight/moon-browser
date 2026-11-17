import AppKit
import WebKit
import XCTest
@testable import Moon

@MainActor
final class FloatingVideoHandoffTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "floating-video-handoff-\(getpid())", 1)
        super.setUp()
    }

    private func withBrowser(_ run: (Browser) async throws -> Void) async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let prefs = browser.prefs
        let saved = (prefs.floatingVideoEnabled, prefs.floatStyle, prefs.floatsOnLeave, prefs.floatsAway)
        let away = Float.benchAway
        Float.benchAway = NSPoint(x: -20_000, y: -20_000)
        prefs.floatingVideoEnabled = true
        prefs.floatStyle = .search
        prefs.floatsOnLeave = false
        prefs.floatsAway = false
        Browsers.register(browser)
        defer {
            browser.land(covering: false)
            browser.unpicture()
            Browsers.discard(browser)
            Float.benchAway = away
            (prefs.floatingVideoEnabled, prefs.floatStyle, prefs.floatsOnLeave, prefs.floatsAway) = saved
        }
        try await run(browser)
    }

    private func js(_ web: WKWebView, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            web.evaluateInSearch(script) { continuation.resume(returning: $0) }
        }
    }

    private func wait(_ description: String, _ condition: () async -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(6))
        while ContinuousClock.now < end {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Timed out waiting for " + description)
    }

    private func video(_ browser: Browser, _ name: String) async throws -> Tab {
        let tab = browser.open(URL(string: "https://pip-regression.invalid/\(name)")!, foreground: false)
        let web = tab.web
        web.stopLoading()
        web.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        web.loadHTMLString("""
        <!doctype html><style>body{margin:0}video{width:640px;height:360px}#hidden{display:none;width:2000px;height:2000px}</style>
        <video id="main"></video><video id="hidden"></video>
        """, baseURL: URL(string: "https://pip-regression.invalid/\(name)"))
        try await wait("fixture document") { await self.js(web, "document.readyState === 'complete' && !!document.getElementById('main')") as? Bool == true }
        _ = await js(web, """
        window.fixtureVideo = function(v) {
          v._paused = false;
          Object.defineProperties(v, {
            paused:{get:()=>v._paused,configurable:true}, ended:{value:false,configurable:true},
            readyState:{value:4,configurable:true}, videoWidth:{value:640,configurable:true},
            videoHeight:{value:360,configurable:true}, duration:{value:120,configurable:true},
            currentTime:{value:0,writable:true,configurable:true}
          });
          v.play=()=>{v._paused=false;return Promise.resolve()};v.pause=()=>{v._paused=true};return v;
        };
        document.querySelectorAll('video').forEach(window.fixtureVideo); true;
        """)
        return tab
    }

    func testSecondPlayingTabTakesOverWindowAndControls() async throws {
        try await withBrowser { browser in
            let a = try await video(browser, "a"), b = try await video(browser, "b")
            browser.select(a, floatPrevious: false)
            browser.toggleFloat()
            try await wait("first floating video") { browser.floating == a.id && browser.floater.showing }
            browser.select(b, floatPrevious: false)
            browser.toggleFloat()
            try await wait("second floating video") { browser.floating == b.id && browser.floater.showing }
            XCTAssertFalse(a.floating)
            XCTAssertTrue(b.floating)
            browser.floater.onSkip?(10)
            try await wait("controls follow the second video") { await self.js(b.web, "document.getElementById('main').currentTime") as? Double == 10 }
            let originalTime = await js(a.web, "document.getElementById('main').currentTime") as? Double
            XCTAssertEqual(originalTime, 0)
            try await wait("first page restored") { await self.js(a.web, "!document.documentElement.classList.contains('office-floating')") as? Bool == true }
        }
    }

    func testSecondBrowserWindowTakesOwnershipWithoutOrphaningFirst() async throws {
        try await withBrowser { first in
            try await withBrowser { second in
                let a = try await video(first, "window-a"), b = try await video(second, "window-b")
                first.select(a, floatPrevious: false)
                first.toggleFloat()
                try await wait("first window's video") { first.floating == a.id }
                second.select(b, floatPrevious: false)
                second.toggleFloat()
                try await wait("second window's ownership") { second.floating == b.id && second.floater.showing }
                XCTAssertNil(first.floating)
                XCTAssertFalse(a.floating)
                XCTAssertTrue(b.floating)
            }
        }
    }

    func testOverlappingRequestsOnlyFloatLatestTabAndRestoreStalePage() async throws {
        try await withBrowser { browser in
            let a = try await video(browser, "race-a"), b = try await video(browser, "race-b")
            browser.select(a, floatPrevious: false)
            browser.toggleFloat()
            browser.select(b, floatPrevious: false)
            browser.toggleFloat()
            try await wait("latest request owns PiP") { browser.floating == b.id && browser.floater.showing }
            try await wait("stale page restored") { await self.js(a.web, "!document.documentElement.classList.contains('office-floating')") as? Bool == true }
            XCTAssertFalse(a.floating)
            XCTAssertTrue(b.floating)
        }
    }

    func testDisablingWhileRequestIsPendingDoesNotOpenAWindow() async throws {
        try await withBrowser { browser in
            let a = try await video(browser, "cancel")
            browser.select(a, floatPrevious: false)
            browser.toggleFloat()
            browser.prefs.floatingVideoEnabled = false
            try await wait("cancelled request restores the page") {
                await self.js(a.web, "!!window.__moonVideoRequest && !document.documentElement.classList.contains('office-floating')") as? Bool == true
            }
            XCTAssertNil(browser.floating)
            XCTAssertFalse(browser.floater.showing)
            let isolated = await js(a.web, "document.documentElement.classList.contains('office-floating')") as? Bool
            XCTAssertEqual(isolated, false)
            browser.toggleFloat()
            XCTAssertNil(FloatingVideoRequest.pending)
        }
    }

    func testHiddenPlayerIsNotSelectedAndReplacementIsRecovered() async throws {
        try await withBrowser { browser in
            let a = try await video(browser, "replacement")
            browser.select(a, floatPrevious: false)
            browser.toggleFloat()
            try await wait("visible player isolated") { await self.js(a.web, "document.querySelector('[data-office-float]')?.id") as? String == "main" }
            _ = await js(a.web, "var old=document.getElementById('main'), next=old.cloneNode();next.id='replacement';old.replaceWith(next);fixtureVideo(next);true")
            try await wait("replacement player recovered") { await self.js(a.web, "document.querySelector('[data-office-float]')?.id") as? String == "replacement" }
            XCTAssertEqual(browser.floating, a.id)
        }
    }

    func testSystemPiPSelectsVisibleVideoAndStaleCleanupCannotStopNewRequest() async throws {
        try await withBrowser { browser in
            let a = try await video(browser, "system")
            _ = await js(a.web, """
            document.querySelectorAll('video').forEach(v=>{
              Object.defineProperty(v,'webkitPresentationMode',{value:'inline',writable:true,configurable:true});
              v.webkitSupportsPresentationMode=()=>true;
              v.webkitSetPresentationMode=mode=>{v.webkitPresentationMode=mode;window.lastPictured=v.id};
            });true;
            """)
            let old = UUID(), current = UUID()
            let entered = await js(a.web, NativePiP.script(toggle: false, request: old)) as? String
            XCTAssertEqual(entered, "in")
            let selected = await js(a.web, "window.lastPictured") as? String
            XCTAssertEqual(selected, "main")
            _ = await js(a.web, NativePiP.script(toggle: false, request: current))
            let stale = await js(a.web, NativePiP.off(request: old)) as? String
            XCTAssertEqual(stale, "superseded")
            let mode = await js(a.web, "document.getElementById('main').webkitPresentationMode") as? String
            XCTAssertEqual(mode, "picture-in-picture")
        }
    }
}

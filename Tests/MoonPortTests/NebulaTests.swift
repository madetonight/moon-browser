import AppKit
import AVFoundation
import WebKit
import XCTest
@testable import Moon

@MainActor
final class NebulaTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "nebula-tests-\(getpid())", 1)
        super.setUp()
    }

    func testCancelClearsTranscriptAndPendingShortcutWithoutStartingAudio() {
        let nebula = Nebula()
        nebula.transcript = "private draft"
        nebula.cancel()
        XCTAssertEqual(nebula.transcript, "")
        XCTAssertEqual(nebula.phase, .ready)
        XCTAssertFalse(nebula.busy)
    }

    func testShortcutIsConfigurableAndUsable() {
        let key = Command.named("edit.nebula")?.defaultKey
        XCTAssertNotNil(key)
        XCTAssertTrue(key?.isUsable == true)
        XCTAssertFalse(key.map(KeyCombo.isReserved) ?? true)
    }

    func testBatchCloseNeedsConfirmationAndExcludesSpoofedTitlesAndPins() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let originalPins = Pins.defs(browser.spaceID)
        let originalShared = Pins.shared(browser.profileID)
        defer {
            browser.closeAll()
            Pins.set(browser.spaceID, originalPins, from: browser)
            _ = Pins.setShared(originalShared, from: browser)
        }
        let youtube = Tab(configuration: Web.configuration())
        youtube.restore(url: URL(string: "https://www.youtube.com/watch?v=1")!, title: "A video")
        let spoof = Tab(configuration: Web.configuration())
        spoof.restore(url: URL(string: "https://example.com/")!, title: "YouTube")
        let pinned = Tab(configuration: Web.configuration())
        pinned.restore(url: URL(string: "https://youtube.com/watch?v=2")!, title: "Pinned video")
        browser.insert(youtube, at: 0); browser.insert(spoof, at: 1); browser.insert(pinned, at: 2)
        browser.pin(pinned)
        let nebula = Nebula()
        nebula.mode = .control
        nebula.open(in: browser)
        defer { nebula.dismiss() }
        nebula.transcript = "close all my YouTube tabs"
        await nebula.apply()
        XCTAssertEqual(nebula.phase, .confirming)
        XCTAssertEqual(nebula.pendingTabs, [youtube.id])
        XCTAssertTrue(browser.tabs.contains { $0.id == youtube.id }, "No tab closes before confirmation")
        nebula.cancel()
        XCTAssertTrue(nebula.pendingTabs.isEmpty)
        XCTAssertTrue(browser.tabs.contains { $0.id == youtube.id })
    }

    func testTidyPreservesTabIdentitySelectionAndPinnedPositions() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let originalPins = Pins.defs(browser.spaceID)
        let originalShared = Pins.shared(browser.profileID)
        defer {
            browser.closeAll()
            Pins.set(browser.spaceID, originalPins, from: browser)
            _ = Pins.setShared(originalShared, from: browser)
        }
        let sites = ["z.example", "b.example", "a.example"]
        let tabs = sites.map { host in
            let tab = Tab(configuration: Web.configuration())
            tab.restore(url: URL(string: "https://\(host)/")!, title: host)
            return tab
        }
        browser.showRow(tabs, active: tabs[1].id)
        browser.pin(tabs[0])
        let selection = browser.activeID
        let pinnedIndex = browser.tabs.firstIndex { $0.id == tabs[0].id }
        XCTAssertEqual(browser.tidyNebulaTabs(), 2)
        XCTAssertEqual(browser.tabs.filter { $0.pin == nil }.map(\.id), [tabs[2].id, tabs[1].id])
        XCTAssertEqual(browser.tabs.firstIndex { $0.id == tabs[0].id }, pinnedIndex)
        XCTAssertEqual(browser.activeID, selection)
        XCTAssertEqual(browser.tidyNebulaTabs(), 0)
    }

    func testAudioConversionYieldsIndependentBuffersAtTheAnalyzerRate() throws {
        let source = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let target = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let conversion = try NebulaAudioConverter(from: source, to: target)
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 2_048))
        input.frameLength = 2_048
        let samples = try XCTUnwrap(input.floatChannelData?.pointee)
        for i in 0..<2_048 { samples[i] = Swift.Float(sin(Double(i) * 0.05)) }
        let first = try conversion.convert(input)
        let second = try conversion.convert(input)
        XCTAssertFalse(first === second)
        XCTAssertEqual(first.format.sampleRate, 16_000)
        XCTAssertGreaterThan(first.frameLength, 0)
        XCTAssertLessThanOrEqual(first.frameLength, first.frameCapacity)
        XCTAssertGreaterThan(second.frameLength, 0)
    }

    func testWebInsertionReplacesSelectionWithLiteralText() async throws {
        let web = try await page("<input id='text' value='alpha beta gamma'>")
        try await evaluate(web, "text.focus(); text.setSelectionRange(6, 10); window.changes = 0; text.addEventListener('input', () => changes++);")
        let captured = try await capture(web)
        XCTAssertTrue(captured)
        let inserted = try await insert(web, "<b>literal</b>")
        XCTAssertTrue(inserted)
        let value = try await web.evaluateJavaScript("document.getElementById('text').value") as? String
        XCTAssertEqual(value, "alpha <b>literal</b> gamma")
        let changes = try await web.evaluateJavaScript("window.changes") as? Int
        XCTAssertEqual(changes, 1)
    }

    func testChangedOrRemovedFieldFailsClosed() async throws {
        let web = try await page("<textarea id='text'>original</textarea>")
        try await evaluate(web, "text.focus()")
        let captured = try await capture(web)
        XCTAssertTrue(captured)
        try await evaluate(web, "text.value = 'changed'")
        let inserted = try await insert(web, "dictated")
        XCTAssertFalse(inserted)
        let value = try await web.evaluateJavaScript("document.getElementById('text').value") as? String
        XCTAssertEqual(value, "changed")
    }

    func testPasswordsAndReadOnlyFieldsAreExcluded() async throws {
        let web = try await page("<input id='secret' type='password'><input id='read' readonly>")
        try await evaluate(web, "secret.focus()")
        let password = try await capture(web)
        XCTAssertFalse(password)
        try await evaluate(web, "read.focus()")
        let readOnly = try await capture(web)
        XCTAssertFalse(readOnly)
    }

    func testBeforeInputCancellationLeavesTheFieldAlone() async throws {
        let web = try await page("<input id='text' value='original'>")
        try await evaluate(web, "text.focus(); text.addEventListener('beforeinput', event => event.preventDefault())")
        let captured = try await capture(web)
        XCTAssertTrue(captured)
        let inserted = try await insert(web, "dictated")
        XCTAssertFalse(inserted)
        let value = try await web.evaluateJavaScript("document.getElementById('text').value") as? String
        XCTAssertEqual(value, "original")
    }

    func testContentEditableUsesTheCapturedSelection() async throws {
        let web = try await page("<div id='text' contenteditable>alpha beta</div>")
        try await evaluate(web, """
        text.focus();
        const range = document.createRange();
        range.setStart(text.firstChild, 6); range.setEnd(text.firstChild, 10);
        getSelection().removeAllRanges(); getSelection().addRange(range);
        """)
        let captured = try await capture(web)
        XCTAssertTrue(captured)
        let inserted = try await insert(web, "gamma")
        XCTAssertTrue(inserted)
        let text = try await web.evaluateJavaScript("document.getElementById('text').textContent") as? String
        XCTAssertEqual(text, "alpha gamma")
    }

    func testNativeInsertionUsesTheOriginalFieldAndRejectsChanges() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 400, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        browser.window = window
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = editor
        window.makeFirstResponder(editor)
        editor.string = "alpha beta"
        editor.setSelectedRange(NSRange(location: 6, length: 4))
        defer { window.contentView = nil; window.close(); browser.closeAll() }
        let destination = await NebulaTarget.capture(in: browser)
        let inserted = await destination?.insert("gamma")
        XCTAssertEqual(inserted, true)
        XCTAssertEqual(editor.string, "alpha gamma")
        destination?.clear()
        let changed = await NebulaTarget.capture(in: browser)
        editor.string = "new draft"
        let rejected = await changed?.insert("wrong")
        XCTAssertEqual(rejected, false)
        XCTAssertEqual(editor.string, "new draft")
        changed?.clear()
    }

    private func page(_ body: String) async throws -> WKWebView {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: Web.configuration())
        web.loadHTMLString("<!doctype html><body>\(body)</body>", baseURL: URL(string: "https://nebula.invalid"))
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while web.isLoading, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        return web
    }

    private func evaluate(_ web: WKWebView, _ script: String) async throws {
        _ = try await web.evaluateJavaScript(script)
    }

    private func capture(_ web: WKWebView) async throws -> Bool {
        try await web.callAsyncJavaScript(NebulaTarget.captureScript, arguments: ["token": "fixture"],
                                         in: nil, contentWorld: Web.world) as? Bool ?? false
    }

    private func insert(_ web: WKWebView, _ text: String) async throws -> Bool {
        try await web.callAsyncJavaScript(NebulaTarget.insertScript, arguments: ["token": "fixture", "text": text],
                                         in: nil, contentWorld: Web.world) as? Bool ?? false
    }
}

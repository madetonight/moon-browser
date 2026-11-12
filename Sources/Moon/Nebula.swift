import AppKit
import AVFoundation
import Speech
import SwiftUI
import WebKit
import MoonCore

@MainActor
final class Nebula: ObservableObject {
    static let shared = Nebula()
    enum Mode: String, CaseIterable { case dictate = "Dictate", control = "Control" }
    enum Phase { case ready, preparing, listening, finishing, review, confirming, working }

    @Published var mode = Mode(rawValue: Store.settings.string(forKey: "nebula.mode") ?? "") ?? .control {
        didSet { Store.settings.set(mode.rawValue, forKey: "nebula.mode") }
    }
    @Published var language = Store.settings.string(forKey: "nebula.language") ?? Locale.current.identifier {
        didSet { Store.settings.set(language, forKey: "nebula.language") }
    }
    @Published private(set) var languages: [String] = []
    @Published private(set) var phase = Phase.ready
    @Published var transcript = ""
    @Published private(set) var status = "Hold the shortcut, speak, then release."
    private(set) weak var browser: Browser?
    private var target: NebulaTarget?
    private var capture: NebulaCapture?
    private var analyzer: SpeechAnalyzer?
    private var setupTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var targetTask: Task<NebulaTarget?, Never>?
    private var generation = UUID()
    private var heldCode: UInt16?
    private var heldFlags: NSEvent.ModifierFlags = []
    private var committed = ""
    private var wantsCapture = false
    @Published private(set) var pendingTabs: [UUID] = []
    private var pendingSpace: UUID?
    private var actionTask: Task<Void, Never>?
    private var resolvedLocales: [String: Locale] = [:]
    private var readyModels: Set<String> = []


    var busy: Bool { phase == .preparing || phase == .listening || phase == .finishing || phase == .working }
    var shortcut: String { ShortcutStore.shared.key(for: "edit.nebula")?.display ?? "your Nebula shortcut" }
    var command: NebulaCommand? { NebulaCommand.parse(transcript) }

    func open(in browser: Browser) {
        if self.browser === browser, browser.nebulaOpen { return }
        dismiss()
        self.browser = browser
        // Capture the destination before a native control in the card takes focus.
        if mode == .dictate { targetTask = Task { await NebulaTarget.capture(in: browser) } }
        browser.translationOpen = false
        browser.orbitOpen = false
        browser.nebulaOpen = true
    }

    func loadLanguages() async {
        let supported = await SpeechTranscriber.supportedLocales
        languages = supported.map(\.identifier).sorted()
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) {
            resolvedLocales[language] = match
            resolvedLocales[match.identifier] = match
            language = match.identifier
        }
    }

    func start() {
        guard !busy, browser?.nebulaOpen == true else { return }
        pendingTabs = []; pendingSpace = nil
        wantsCapture = true
        transcript = ""; committed = ""
        status = "Preparing on-device speech…"
        phase = .preparing
        let turn = UUID()
        generation = turn
        setupTask = Task { [self] in
            do {
                guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
                let locale: Locale
                if let cached = resolvedLocales[language] { locale = cached }
                else {
                    guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else { throw Failure.language }
                    locale = supported; resolvedLocales[language] = supported
                }
                if mode == .dictate {
                    if targetTask == nil, let browser { targetTask = Task { await NebulaTarget.capture(in: browser) } }
                    target = await targetTask?.value
                    guard target != nil else { throw Failure.field }
                }
                try Task.checkCancellation()
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                try Task.checkCancellation()
                guard granted else { throw Failure.permission }
                guard generation == turn else { return }
                let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
                if !readyModels.contains(locale.identifier) {
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                        status = "Downloading Apple’s speech model for this language…"
                        try await request.downloadAndInstall()
                    }
                    readyModels.insert(locale.identifier)
                }
                try Task.checkCancellation()
                guard generation == turn, (NSApp.isActive && browser?.window?.isKeyWindow == true) || Store.testing
                else { throw CancellationError() }
                let capture = NebulaCapture()
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber], considering: capture.inputFormat) else { throw Failure.unavailable }
                let analyzer = SpeechAnalyzer(modules: [transcriber],
                    options: .init(priority: .userInitiated, modelRetention: .lingering))
                self.analyzer = analyzer
                let context = AnalysisContext()
                let sites = browser?.displayedTabs.filter { !$0.shy && !$0.bench && $0.page == nil }.prefix(24).flatMap {
                    [String($0.label.prefix(80)), $0.pageAddress?.host() ?? ""]
                } ?? []
                context.contextualStrings[.general] = ["Moon", "Nebula", "YouTube", "Gmail", "Google", "GitHub"] + sites
                try await analyzer.setContext(context)
                try Task.checkCancellation()
                guard generation == turn, browser?.window?.isKeyWindow == true || Store.testing else { throw CancellationError() }
                guard wantsCapture else {
                    await analyzer.cancelAndFinishNow()
                    guard generation == turn else { return }
                    self.analyzer = nil
                    setupTask = nil
                    phase = .ready
                    status = "Ready. Hold the shortcut again to speak."
                    return
                }
                self.capture = capture
                resultsTask = Task { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            guard let self, self.generation == turn else { return }
                            self.receive(String(result.text.characters), final: result.isFinal)
                        }
                    } catch {
                        if let self, self.generation == turn, !Task.isCancelled { self.fail(error) }
                    }
                }
                phase = .listening
                status = "Listening. Release to act."
                let inputs = try capture.start(format: format)
                try await analyzer.start(inputSequence: inputs)
                try Task.checkCancellation()
                guard generation == turn else { return }
                deadlineTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(120))
                    guard !Task.isCancelled, self?.generation == turn else { return }
                    self?.fail(Failure.timeout)
                }
            } catch {
                if generation == turn {
                    if error is CancellationError { cancel() }
                    else { fail(error) }
                }
            }
        }
    }

    private func receive(_ text: String, final: Bool) {
        let segment = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = [committed, segment].filter { !$0.isEmpty }.joined(separator: " ")
        let bounded = String(combined.prefix(16_000))
        transcript = NebulaTranscript.withoutTrailingPeriod(bounded)
        // Keep sentence boundaries between recognition segments, while the
        // displayed and inserted transcript never has an automatic final dot.
        if final { committed = bounded }
        if combined.count > 16_000 { fail(Failure.timeout) }
    }

    func stop() {
        heldCode = nil
        wantsCapture = false
        if phase == .preparing { status = "Preparing speech. Hold again when ready."; return }
        guard phase == .listening, let analyzer else { return }
        capture?.stop()
        capture = nil
        deadlineTask?.cancel()
        phase = .finishing
        status = "Finishing your transcript…"
        let turn = generation
        finishTask = Task {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                await resultsTask?.value
                guard generation == turn else { return }
                self.analyzer = nil
                resultsTask = nil
                setupTask = nil
                phase = .review
                status = transcript.isEmpty ? "No speech detected. Hold to try again." : "Working…"
                deadlineTask?.cancel()
                deadlineTask = nil
                if !transcript.isEmpty {
                    actionTask = Task { [weak self] in await self?.apply() }
                }
            } catch {
                if generation == turn { fail(error) }
            }
        }
        deadlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, self?.generation == turn, self?.phase == .finishing else { return }
            self?.fail(Failure.timeout)
        }
    }

    func cancel() {
        generation = UUID()
        heldCode = nil
        wantsCapture = false
        pendingTabs = []; pendingSpace = nil
        actionTask?.cancel(); actionTask = nil
        setupTask?.cancel(); setupTask = nil
        finishTask?.cancel(); finishTask = nil
        resultsTask?.cancel(); resultsTask = nil
        deadlineTask?.cancel(); deadlineTask = nil
        capture?.stop(); capture = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        transcript = ""; committed = ""
        phase = .ready
        status = "Hold the shortcut, speak, then release."
    }

    private func fail(_ error: Error) {
        readyModels = []
        let words = transcript
        cancel()
        transcript = words
        phase = words.isEmpty ? .ready : .review
        status = error.localizedDescription
    }

    func dismiss() {
        let oldTargetTask = targetTask
        oldTargetTask?.cancel()
        Task { (await oldTargetTask?.value)?.clear() }
        targetTask = nil
        target?.clear(); target = nil
        cancel()
        browser?.nebulaOpen = false
        browser = nil
    }

    func suspend(in owner: Browser) {
        guard browser === owner else { return }
        dismiss()
    }

    /// Use Moon's configurable shortcut, including key-up and modifier release.
    func handle(_ event: NSEvent, in owner: Browser) -> Bool {
        guard !ShortcutStore.shared.recording else { return false }
        if let code = heldCode, browser === owner {
            if event.type == .keyUp, event.keyCode == code { stop(); return true }
            if event.type == .flagsChanged, !event.modifierFlags.isSuperset(of: heldFlags) { stop(); return false }
            if event.type == .keyDown, event.keyCode == code { return true }
        }
        if event.type == .keyDown, event.keyCode == 53, browser === owner, owner.nebulaOpen {
            dismiss(); return true
        }
        guard event.type == .keyDown, !event.isARepeat,
              let key = ShortcutStore.shared.key(for: "edit.nebula"), KeyCombo(event: event) == key else { return false }
        open(in: owner)
        guard !busy else { return true }
        heldCode = event.keyCode
        heldFlags = key.flags.intersection([.command, .control, .option, .shift])
        start()
        return true
    }

    func apply() async {
        guard !busy, let browser, browser.nebulaOpen else { return }
        transcript = NebulaTranscript.withoutTrailingPeriod(transcript)
        if mode == .dictate {
            guard let target else { status = Failure.field.localizedDescription; return }
            phase = .working
            if await target.insert(transcript) { dismiss() }
            else { phase = .review; status = "The field changed. Copy your words and choose the field again." }
            return
        }
        guard let request = NebulaRequest.resolve(transcript) else { status = "No speech detected. Hold the shortcut and try again."; return }
        let command: NebulaCommand
        switch request {
        case .command(let resolved): command = resolved
        case .googleSearch(let query):
            guard let url = NebulaRequest.googleURL(for: query) else { return }
            dismiss(); browser.open(url, foreground: true, from: browser.active)
            return
        case .unsupportedAddress:
            status = "Say a website name or web address. Local files and sign-in details aren't opened by voice."
            return
        }
        if command == .closeTab || { if case .closeMatching = command { return true }; return false }() {
            let matches: [Tab]
            if case .closeMatching(let name) = command { matches = matchingTabs(name, in: browser).filter { $0.pin == nil } }
            else { matches = (browser.active.map { [$0] } ?? []).filter { $0.pin == nil } }
            guard !matches.isEmpty else { status = "No matching unpinned tabs in this space."; return }
            pendingTabs = matches.map(\.id)
            pendingSpace = browser.spaceID
            phase = .confirming
            status = "Close \(matches.count) \(matches.count == 1 ? "tab" : "tabs") in this space? Pinned tabs stay."
            return
        }
        if case .switchSpace(let name) = command {
            switchSpace(named: name, in: browser)
            return
        }
        if case .switchTab(let name) = command {
            let exactSpaces = browser.spaces.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            if exactSpaces.count == 1 { switchSpace(named: name, in: browser); return }
            let matches = browser.displayedTabs.filter {
                $0.label.localizedCaseInsensitiveContains(name) || ($0.pageAddress?.host()?.localizedCaseInsensitiveContains(name) ?? false)
            }
            guard matches.count == 1, let tab = matches.first else {
                status = matches.isEmpty ? "No matching tab. Try its title or domain." : "Several tabs match. Say a more specific title."
                return
            }
            dismiss(); browser.select(tab)
            return
        }
        dismiss()
        switch command {
        case .newTab: browser.launch()
        case .newPrivateTab: browser.newShyTab()
        case .closeTab: browser.closeFront()
        case .back: browser.back()
        case .forward: browser.forward()
        case .reload: browser.reload()
        case .nextTab: browser.step(1)
        case .previousTab: browser.step(-1)
        case .bookmarks: browser.bookmarking = true
        case .downloads: browser.hoarding = true
        case .translate: browser.openTranslation()
        case .orbit: browser.orbitOpen = true
        case .bookmark: browser.bookmarkCurrent()
        case .mute:
            if let tab = browser.active, !tab.muted { tab.toggleMute() }
        case .zoomIn: browser.zoom(by: 1.1)
        case .zoomOut: browser.zoom(by: 1 / 1.1)
        case .resetZoom: browser.resetZoom()
        case .scroll(let up):
            browser.active?.built?.callAsyncJavaScript(
                "window.scrollBy({top: (up ? -1 : 1) * innerHeight * 0.75, behavior: 'smooth'});",
                arguments: ["up": up], in: nil, in: Web.world) { _ in }
        case .search(let query):
            if let url = NebulaRequest.googleURL(for: query) { browser.open(url, foreground: true, from: browser.active) }
        case .open(let url): browser.open(url, foreground: true, from: browser.active)
        case .summarize: browser.summarizePage()
        case .tidy:
            let count = browser.tidyNebulaTabs()
            browser.announce(count > 1 ? "Arranged \(count) tabs by website" : "Tabs are already tidy")
        case .switchTab, .switchSpace, .closeMatching: break
        }
    }

    func runExample(_ words: String) {
        guard !busy else { return }
        mode = .control
        transcript = words
        phase = .review
        actionTask = Task { [weak self] in await self?.apply() }
    }

    func confirmClose() {
        guard phase == .confirming, let browser, browser.spaceID == pendingSpace,
              browser.window?.isKeyWindow == true || Store.testing else { return }
        let ids = Set(pendingTabs)
        dismiss()
        browser.closeNebulaTabs(ids)
    }

    private func switchSpace(named name: String, in browser: Browser) {
        guard browser.prefs.usesSpaces else { status = "Enable Spaces in Settings to switch between them."; return }
        let matches = browser.spaces.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        guard matches.count == 1, let space = matches.first else {
            status = "Say the exact name of one of your spaces."
            return
        }
        dismiss()
        browser.switchSpace(to: space.id)
    }

    private func matchingTabs(_ name: String, in browser: Browser) -> [Tab] {
        let aliases = ["youtube": ["youtube.com", "youtu.be"], "gmail": ["mail.google.com"], "x": ["x.com", "twitter.com"]]
        return browser.displayedTabs.filter { tab in
            guard tab.isWeb, let host = tab.pageAddress?.host()?.lowercased() else { return false }
            if let domains = aliases[name] { return domains.contains { host == $0 || host.hasSuffix("." + $0) } }
            return host == name || host.hasSuffix("." + name) || host.split(separator: ".").contains(Substring(name)) || tab.label.localizedCaseInsensitiveContains(name)
        }
    }

    enum Failure: LocalizedError {
        case unavailable, language, field, permission, timeout
        var errorDescription: String? {
            switch self {
            case .unavailable: "On-device speech is unavailable on this Mac."
            case .language: "Choose a language supported by on-device speech."
            case .field: "Focus a text field, then open Nebula again. Password fields are excluded."
            case .permission: "Enable Moon’s microphone access in System Settings → Privacy & Security → Microphone."
            case .timeout: "Transcription took too long. Your words are available for review."
            }
        }
    }
}

import AppKit
import SwiftUI
import WebKit
import MoonCore

@MainActor
final class LinkPressure {
    private weak var view: PageView?
    private var monitor: Any?
    private var timer: DispatchWorkItem?
    private var gesture = LinkPressureGesture()
    private var url: URL?
    private var swallowUp = false
    private var point = NSPoint.zero
    private var turn = UUID()
    init(view: PageView) { self.view = view }
    func watch() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.pressure, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.take(event) == true ? nil : event }
        }
    }
    func stop() {
        timer?.cancel(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; url = nil; swallowUp = false; gesture.cancel(); turn = UUID()
    }
    private func take(_ event: NSEvent) -> Bool {
        guard let view, event.window === view.window, view.window != nil else { return false }
        if event.type == .leftMouseUp, swallowUp {
            swallowUp = false
            timer?.cancel(); timer = nil
            if let link = url { view.suppressedForceLink = (link, Date().addingTimeInterval(1.5)) }
            if let action = gesture.end(at: event.timestamp) { perform(action) }
            url = nil
            return true
        }
        if event.type == .pressure && event.stage < 2 {
            guard url != nil else { return false }
            if let link = url { view.suppressedForceLink = (link, Date().addingTimeInterval(1.5)) }
            timer?.cancel(); timer = nil
            if let action = gesture.end(at: event.timestamp) { perform(action) }
            url = nil
            return true
        }
        guard event.type == .pressure, event.stage >= 2, Shared.prefs.forceClickLinks else { return false }
        if url != nil { return true }
        var hit = view.window?.contentView?.hitTest(event.locationInWindow)
        while let current = hit, current !== view { hit = current.superview }
        guard hit === view, let link = view.forceLink, LinkInsight.allowed(link) else { return false }
        url = link; swallowUp = true; point = event.locationInWindow; turn = UUID()
        gesture.begin(at: event.timestamp)
        view.suppressedForceLink = (link, Date().addingTimeInterval(1.5))
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        let work = DispatchWorkItem { [weak self] in
            guard let self, let action = gesture.hold(at: event.timestamp + LinkPressureGesture.holdDuration) else { return }
            perform(action)
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + LinkPressureGesture.holdDuration, execute: work)
        return true
    }
    private func perform(_ action: LinkPressureGesture.Action) {
        guard let view, let url else { return }
        let token = turn, anchor = point
        // The isolated hover relay supplies its WebKit frame. This also works
        // for iframe links and open shadow roots, without traversing origins.
        view.callAsyncJavaScript("""
        const anchor = window.__searchLinks?.anchor;
        if (!anchor?.isConnected || !anchor.matches(':hover')) return '';
        try { return new URL(anchor.href?.baseVal || anchor.href || '', anchor.baseURI).href; } catch { return ''; }
        """, arguments: [:], in: view.forceLinkFrame, in: .defaultClient) { [weak self, weak view] result in
                guard let self, turn == token, let view, case .success(let value) = result,
                      let text = value as? String, URL(string: text) == url else { return }
                if action == .preview { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
                view.onForceLink?(url, action == .preview, anchor)
            }
    }
}

/// A transient, bounded metadata reader. It never uses the user's cookies,
/// saves history, sends page text to AI, or runs the linked page's JavaScript.
@MainActor
final class LinkInsight: NSObject, ObservableObject, WKNavigationDelegate, Identifiable {
    let id = UUID()
    let url: URL
    let anchor: NSPoint
    @Published var title: String
    @Published var summary = "Reading this link…"
    init(url: URL, anchor: NSPoint) { self.url = url; self.anchor = anchor; title = url.host() ?? "Link" }
    static func allowed(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil && url.user == nil && url.password == nil
    }
    func load() async {
        let configuration = Web.configuration(shy: true)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 500), configuration: configuration)
        web.navigationDelegate = self
        defer { web.stopLoading(); web.navigationDelegate = nil }
        web.load(URLRequest(url: url, timeoutInterval: 5))
        do {
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(75))
                if !web.isLoading { break }
            }
            try Task.checkCancellation()
            let result = try await web.callAsyncJavaScript("""
            const title = document.querySelector('meta[property="og:title"]')?.content || document.title;
            const description = document.querySelector('meta[name="description"],meta[property="og:description"]')?.content;
            const paragraph = [...document.querySelectorAll('article p,main p,p')].map(p=>p.textContent.trim()).find(t=>t.length>70);
            return {title: String(title || '').slice(0,180), description: String(description || paragraph || '').slice(0,700)};
            """, arguments: [:], in: nil, contentWorld: Web.world) as? [String: String]
            try Task.checkCancellation()
            if let text = result?["title"], !text.isEmpty { title = text }
            summary = result?["description"].flatMap { $0.isEmpty ? nil : $0 } ?? "This page has no short description. Hold a force-click to preview it."
        } catch {
            if !Task.isCancelled { summary = "A quick description isn’t available. You can still preview the page." }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url.map(Self.allowed) == true && !navigationAction.shouldPerformDownload ? .allow : .cancel)
    }
}

struct LinkInsightOverlay: View {
    @ObservedObject var browser: Browser
    var body: some View {
        if let insight = browser.linkInsight {
            GeometryReader { geometry in
                Color.black.opacity(0.001).onTapGesture { browser.linkInsight = nil }
                LinkInsightCard(insight: insight) {
                    browser.linkInsight = nil
                    if let tab = browser.active { browser.peek(insight.url, from: tab) }
                } close: { browser.linkInsight = nil }
                    .frame(width: min(320, max(0, geometry.size.width - 24)))
                    .position(x: min(max(172, insight.anchor.x + 160), max(172, geometry.size.width - 172)),
                              y: min(max(130, geometry.size.height - insight.anchor.y + 110), max(130, geometry.size.height - 130)))
            }.clipped().onChange(of: browser.activeID) { _, _ in browser.linkInsight = nil }
                .onExitCommand { browser.linkInsight = nil }
        }
    }
}

private struct LinkInsightCard: View {
    @ObservedObject var insight: LinkInsight
    let preview: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(insight.url.host() ?? "Website", systemImage: "globe").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close insight")
            }
            Text(insight.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            Text(insight.summary).font(.system(size: 12)).lineLimit(6).foregroundStyle(.secondary)
            Button("Preview Page", action: preview).buttonStyle(.plain).font(.system(size: 11, weight: .medium))
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6).task { await insight.load() }
    }
}

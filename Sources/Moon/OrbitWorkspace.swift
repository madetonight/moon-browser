import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers
import MoonCore

/// Native navigation and summaries, with the complete upstream tools in an
/// isolated WebKit workspace. No reduced imitation of the ActivityWatch UI.
struct OrbitWorkspace: View {
    @ObservedObject var orbit: Orbit
    let profile: UUID
    @ObservedObject private var engine = OrbitEngine.shared
    @State private var selection: Section? = .overview
    @State private var apiKey = ""
    @State private var keyError = false
    @State private var workspaceRevision = UUID()

    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview", moon = "Moon activity", activity = "All activity", timeline = "Timeline"
        case trends = "Trends", spiral = "Time spiral", categories = "Categories", work = "Work time"
        case billing = "Billable hours", stopwatch = "Stopwatch", reports = "Reports", data = "Data & imports"
        case queries = "Query explorer", alerts = "Alerts", search = "Search", graph = "Activity graph"
        case analysis = "AI analysis", privacy = "Privacy filters", settings = "Engine settings", setup = "Watchers & sync"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .overview: return "sparkles"
            case .moon: return "moon"
            case .activity: return "chart.bar"
            case .timeline: return "list.bullet.rectangle"
            case .trends: return "chart.xyaxis.line"
            case .spiral: return "circle.dotted"
            case .categories: return "tag"
            case .work: return "briefcase"
            case .billing: return "clock.badge.checkmark"
            case .stopwatch: return "stopwatch"
            case .reports: return "doc.text"
            case .data: return "externaldrive"
            case .queries: return "curlybraces"
            case .alerts: return "bell"
            case .search: return "magnifyingglass"
            case .graph: return "point.3.connected.trianglepath.dotted"
            case .analysis: return "text.bubble"
            case .privacy: return "hand.raised"
            case .settings: return "gearshape"
            case .setup: return "puzzlepiece.extension"
            }
        }
        var route: String? {
            switch self {
            case .activity: return "/home"
            case .timeline: return "/timeline"
            case .trends: return "/trends"
            case .spiral: return "/timespiral"
            case .categories: return "/settings/categorization"
            case .work: return "/work-report"
            case .billing: return "/billing"
            case .stopwatch: return "/stopwatch"
            case .reports: return "/report"
            case .data: return "/buckets"
            case .queries: return "/query"
            case .alerts: return "/alerts"
            case .search: return "/search"
            case .graph: return "/graph"
            case .analysis: return "/analysis/activity"
            case .privacy: return "/settings/privacy"
            case .settings: return "/settings"
            default: return nil
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 155, ideal: 180, max: 230)
        } detail: {
            Group {
                if selection == .moon {
                    OrbitMoonDetail(orbit: orbit, profile: profile)
                } else if selection == .setup {
                    setup
                } else if let route = selection?.route {
                    if engine.enabled {
                        OrbitEngineWebView(route: route).id(route + workspaceRevision.uuidString)
                    } else {
                        setup
                    }
                } else {
                    overview
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Orbit")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(selection?.rawValue ?? "Overview").font(.system(size: 13, weight: .medium))
            }
            ToolbarItem {
                Button { engine.refresh(); workspaceRevision = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh local activity").disabled(!engine.enabled || engine.refreshing)
            }
        }
        .task { if engine.enabled { engine.refresh() } }
        .alert("Could not save the local API key", isPresented: $keyError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Check Keychain access and try again. Keys must be a single line under 4 KB.") }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Orbit", systemImage: "sparkles").font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("A little perspective on your day.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Today").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 35) {
                    metric("Mac active time", engine.connected ? Orbit.duration(engine.activeSeconds) : "—")
                    metric("Moon browsing", Orbit.duration(orbit.rows(profile: profile, days: 1).reduce(0) { $0 + $1.seconds }))
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Top applications").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("All activity") { selection = .activity }.buttonStyle(.link).font(.system(size: 11))
                    }
                    if engine.apps.isEmpty {
                        Text(engine.connected ? "Application totals appear after the window and away watchers have recorded activity." : "Connect the local engine for applications, categories and your complete activity timeline.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    } else {
                        OrbitSites(rows: Array(engine.apps.prefix(6)))
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Top websites in Moon").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("See breakdown") { selection = .moon }.buttonStyle(.link).font(.system(size: 11))
                    }
                    let sites = Orbit.sites(orbit.rows(profile: profile, days: 1))
                    if sites.isEmpty {
                        Text("Enable Moon tracking to begin. Private tabs stay private.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else { OrbitSites(rows: Array(sites.prefix(5))) }
                    Toggle("Track Moon website time", isOn: $orbit.enabled).toggleStyle(.switch).controlSize(.small)
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(engine.status).font(.system(size: 11, weight: .medium))
                        Text("Activity stays on this Mac unless you configure sync or explicitly share it.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(engine.enabled ? "Setup" : "Connect") { selection = .setup }
                }
            }.padding(26)
        }
        .background(.background)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("One local engine. Your whole picture.").font(.system(size: 22, weight: .semibold))
                Text("Orbit uses the official ActivityWatch engine for Mac-wide activity, its complete data tools, and compatible plugins. Moon remains protected and small; ActivityWatch runs separately.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open ActivityWatch…") { engine.openEngine() }
                    Button(engine.enabled ? "Retry connection" : "Connect locally") { engine.connect() }
                        .disabled(engine.refreshing)
                }
                Label(engine.status, systemImage: engine.connected ? "checkmark.circle" : "circle.dotted")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if engine.enabled {
                    Button("Disconnect Orbit") { engine.disconnect() }.buttonStyle(.link)
                }
                DisclosureGroup("Local API key, if required") {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("ActivityWatch API key", text: $apiKey).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Save in Keychain & connect") {
                                if engine.saveAPIKey(apiKey) { apiKey = ""; engine.connect() } else { keyError = true }
                            }.disabled(apiKey.isEmpty)
                            Button("Remove saved key") { if !engine.saveAPIKey("") { keyError = true } }
                        }
                        Text("Used only by native summaries and Moon heartbeats to the fixed local endpoint. The full workspace uses ActivityWatch’s own sign-in; this key is never inserted into web scripts or URLs.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
                Divider()
                explanation("Watchers & permissions", "Use ActivityWatch’s menu bar icon to start or pause the window and away watchers, manage modules, and choose start at login. Window titles need macOS Accessibility permission. Orbit does not grant it or start Mac-wide recording for you.")
                explanation("Browsers & editors", "Install ActivityWatch’s browser extensions or editor watchers for Chrome, Firefox, VS Code, JetBrains, Vim, Zed and other supported apps. Their buckets appear in Data & imports and the full Activity view. Enabling Moon tracking shares only website names with the connected local engine, never private tabs, paths or searches.")
                explanation("Sync & multiple devices", "ActivityWatch’s optional aw-sync module uses a folder you choose. Configure it on each device, then select the synced devices in All activity. Setup is manual; settings and deletions do not sync. Orbit does not enable cloud storage or expose the API to your network.")
                explanation("All the advanced tools", "Timeline filters and swimlanes, category sets and rule priorities, work and billable reports, stopwatch, alerts, search, graphs, query explorer, raw events, import/export and privacy filters are available in the workspace. Engine/API-key authentication, optional integrations and AI services keep ActivityWatch’s own setup and consent requirements.")
                Text("Local connection: 127.0.0.1:5600 · ActivityWatch 0.14 or later recommended")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }.padding(26)
        }.background(.background)
    }

    private func explanation(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A separate, nonpersistent web store prevents the activity workspace from
/// inheriting Moon website sessions, passwords, extensions or native bridges.
struct OrbitEngineWebView: NSViewRepresentable {
    let route: String
    // WebKit's content blocker grammar does not support regex alternation.
    static let networkRules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^http://127[.]0[.]0[.]1:5600/"},"action":{"type":"ignore-previous-rules"}}]"#
    private static let store = WKWebsiteDataStore.nonPersistent()
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.store
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let css = "body,input,button,select,textarea{font-family:-apple-system,BlinkMacSystemFont,sans-serif!important}body{font-size:13px!important}.navbar-brand{display:none!important}.container{max-width:100%!important}td,th{font-variant-numeric:tabular-nums}"
        let script = "const s=document.createElement('style');s.textContent=\(String(decoding: try! JSONEncoder().encode(css), as: UTF8.self));document.head.appendChild(s);"
        config.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.isInspectable = false
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "moon-orbit-local-only", encodedContentRuleList: Self.networkRules) { [weak view] list, _ in
            guard let view else { return }
            guard let list else { Coordinator.unavailable(view); return }
            view.configuration.userContentController.add(list)
            view.load(URLRequest(url: ActivityWatchEndpoint.workspace(route)))
        }
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        static func unavailable(_ view: WKWebView) {
            view.loadHTMLString("<html><head><meta name='color-scheme' content='light dark'></head><body style='font:13px -apple-system;margin:40px'><h2>Workspace unavailable</h2><p>Open ActivityWatch, then use Refresh to retry the local workspace.</p></body></html>", baseURL: nil)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { Self.unavailable(webView) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { Self.unavailable(webView) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let allowed = ActivityWatchEndpoint.allows(url) || url.absoluteString == "about:blank"
                || (url.scheme == "blob" && url.absoluteString.hasPrefix("blob:http://127.0.0.1:5600/"))
            guard allowed else {
                if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? ""), url.user == nil, url.password == nil {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel); return
            }
            if action.shouldPerformDownload { decisionHandler(.download) }
            else if url.scheme == "blob" { decisionHandler(.cancel) }
            else if action.targetFrame == nil { webView.load(action.request); decisionHandler(.cancel) }
            else { decisionHandler(.allow) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .download)
        }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath: suggestedFilename).lastPathComponent
            completionHandler(panel.runModal() == .OK ? panel.url : nil)
        }
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert(); alert.messageText = "Orbit"; alert.informativeText = String(message.prefix(4000)); alert.runModal(); completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert(); alert.messageText = "Orbit"; alert.informativeText = String(message.prefix(4000))
            alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}

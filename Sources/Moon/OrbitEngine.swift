import Foundation
import AppKit
import Combine
import MoonCore
import Security

/// Official ActivityWatch stays outside Moon's sandbox. This client only talks
/// to the fixed loopback endpoint, with bounded, credential-free HTTP requests.
@MainActor final class OrbitEngine: ObservableObject {
    static let shared = OrbitEngine()
    @Published private(set) var connected = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var version = ""
    @Published private(set) var apps: [(host: String, seconds: Double)] = []
    @Published private(set) var activeSeconds = 0.0
    @Published private(set) var watcherCount = 0
    @Published private(set) var refreshing = false
    @Published private(set) var enabled = Store.settings.bool(forKey: "orbit.engine")
    private var hostname = ""
    private var bucket: String?
    private var sending = false
    private var pauseRequested = false
    private var bucketActive = false
    private var generation = UUID()
    private var requestTask: Task<Void, Never>?
    private var apiKey: String?
    private var keyLoaded = false

    private init() {}

    /// A native-only credential. Never placed in a URL, web script or defaults.
    func saveAPIKey(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 4096, !value.contains("\r"), !value.contains("\n") else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "org.moonbrowser.Moon.OrbitEngine",
                                    kSecAttrAccount as String: "loopback-api"]
        let result: OSStatus
        if value.isEmpty {
            let removed = SecItemDelete(query as CFDictionary)
            result = removed == errSecItemNotFound ? errSecSuccess : removed
        } else {
            let data = Data(value.utf8)
            let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if updated == errSecItemNotFound {
                var item = query; item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                result = SecItemAdd(item as CFDictionary, nil)
            } else { result = updated }
        }
        guard result == errSecSuccess else { return false }
        apiKey = value.isEmpty ? nil : value; keyLoaded = true
        return true
    }

    private func loadAPIKey() {
        guard !keyLoaded else { return }
        var value: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "org.moonbrowser.Moon.OrbitEngine",
                                    kSecAttrAccount as String: "loopback-api",
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let result = SecItemCopyMatching(query as CFDictionary, &value)
        if result == errSecSuccess, let data = value as? Data { apiKey = String(data: data, encoding: .utf8) }
        keyLoaded = true
    }

    func connect() {
        enabled = true; Store.settings.set(true, forKey: "orbit.engine")
        loadAPIKey()
        refresh()
    }
    func disconnect() {
        generation = UUID(); requestTask?.cancel(); requestTask = nil
        enabled = false; connected = false; refreshing = false
        apps = []; activeSeconds = 0; watcherCount = 0; bucket = nil
        status = "Not connected"; Store.settings.set(false, forKey: "orbit.engine")
    }
    func refresh() {
        guard enabled, !refreshing else { return }
        loadAPIKey()
        refreshing = true
        let turn = generation
        requestTask = Task {
            defer { if generation == turn { refreshing = false } }
            do {
                let infoData = try await request(["info"])
                let info = try JSONDecoder().decode(Info.self, from: infoData)
                guard generation == turn, !Task.isCancelled else { return }
                hostname = info.hostname; version = info.version; connected = true
                let buckets = try JSONDecoder().decode([String: Bucket].self, from: await request(["buckets", ""]))
                guard generation == turn, !Task.isCancelled else { return }
                watcherCount = buckets.count
                guard let window = buckets.keys.sorted().first(where: { buckets[$0]?.type == "currentwindow" && buckets[$0]?.hostname == hostname }),
                      let afk = buckets.keys.sorted().first(where: { buckets[$0]?.type == "afkstatus" && buckets[$0]?.hostname == hostname }) else {
                    apps = []; activeSeconds = 0
                    status = "Connected · start window and away watchers for Mac totals"
                    return
                }
                let query = [
                    "events = query_bucket(\(ActivityWatchEndpoint.literal(window)));",
                    "afk = query_bucket(\(ActivityWatchEndpoint.literal(afk)));",
                    "afk = filter_keyvals(afk, 'status', ['not-afk']);",
                    "events = filter_period_intersect(events, afk);",
                    "RETURN = sort_by_duration(merge_events_by_keys(events, ['app']));"
                ]
                let formatter = ISO8601DateFormatter()
                let start = Calendar.current.startOfDay(for: Date())
                let body: [String: Any] = ["timeperiods": [formatter.string(from: start) + "/" + formatter.string(from: Date())], "query": query]
                let result = try JSONDecoder().decode([[Event]].self, from: await request(["query", ""], body: body))
                guard generation == turn, !Task.isCancelled else { return }
                apps = (result.first ?? []).compactMap { event in
                    guard event.duration.isFinite, event.duration > 0, let app = event.data.app, !app.isEmpty else { return nil }
                    return (host: app, seconds: event.duration)
                }
                activeSeconds = apps.reduce(0) { $0 + $1.seconds }
                status = "Connected · ActivityWatch \(version)"
            } catch {
                guard generation == turn else { return }
                connected = false; apps = []; activeSeconds = 0
                status = "Engine unavailable or access required. Open ActivityWatch and retry."
            }
        }
    }

    /// Sharing requires both the engine connection and Moon's opt-in tracker.
    /// Only a sanitized website origin is sent; private tabs never reach here.
    func heartbeat(_ site: OrbitLedger.Site) {
        guard enabled, connected, !sending else { return }
        sending = true
        let turn = generation
        Task {
            defer {
                sending = false
                if pauseRequested { pause() }
            }
            do {
                let name = "aw-watcher-web-moon_\(site.profile.uuidString)_\(hostname)"
                if bucket != name {
                    if let bucket, bucketActive { try await stopEvent(bucket) }
                    bucketActive = false
                    do { _ = try await request(["buckets", name]) }
                    catch {
                        _ = try await request(["buckets", name], body: ["client": "aw-watcher-web-moon", "type": "web.tab.current", "hostname": "!local"])
                    }
                    guard generation == turn, enabled else { return }
                    bucket = name
                }
                guard generation == turn, enabled, Orbit.shared.enabled else { return }
                _ = try await request(["buckets", name, "heartbeat"], query: [URLQueryItem(name: "pulsetime", value: "7.5")],
                                      body: ["timestamp": ISO8601DateFormatter().string(from: Date()), "duration": 0,
                                             "data": ["url": site.origin, "title": site.host, "audible": site.audible, "incognito": false]])
                bucketActive = true
            } catch {
                // Local native time remains available if the engine goes away.
                if generation == turn { bucket = nil }
            }
        }
    }

    /// A redacted boundary stops upstream timeline flooding through a private
    /// tab, an internal page, or another app. It carries no page information.
    func pause() {
        guard enabled, connected else { pauseRequested = false; return }
        if sending { pauseRequested = true; return }
        pauseRequested = false
        guard let bucket, bucketActive else { return }
        bucketActive = false; sending = true
        Task {
            defer { sending = false }
            try? await stopEvent(bucket)
        }
    }

    private func stopEvent(_ bucket: String) async throws {
        _ = try await request(["buckets", bucket, "heartbeat"], query: [URLQueryItem(name: "pulsetime", value: "7.5")],
                              body: ["timestamp": ISO8601DateFormatter().string(from: Date()), "duration": 0,
                                     "data": ["url": "", "title": "", "audible": false, "incognito": true]])
    }

    private func request(_ path: [String], query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        var parts = URLComponents(url: ActivityWatchEndpoint.api(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var request = URLRequest(url: parts.url!)
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await BoundedFetch.data(request: request, policy: .sameOrigin(ActivityWatchEndpoint.base), limit: 4 * 1024 * 1024, timeout: 8)
    }

    func openEngine() {
        let app = URL(fileURLWithPath: "/Applications/ActivityWatch.app")
        guard FileManager.default.fileExists(atPath: app.path) else {
            NSWorkspace.shared.open(URL(string: "https://activitywatch.net/downloads/")!)
            return
        }
        NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, _ in }
    }

    private struct Info: Decodable { let hostname: String; let version: String }
    private struct Bucket: Decodable { let type: String; let hostname: String }
    private struct Event: Decodable {
        let duration: Double
        let data: AppData
        struct AppData: Decodable { let app: String? }
    }
}

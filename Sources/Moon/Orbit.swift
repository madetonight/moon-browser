import AppKit
import SwiftUI
import Combine
import MoonCore
import UniformTypeIdentifiers

/// One five-second heartbeat, only while enabled. No web script, permission,
/// network request or page content is involved in activity collection.
@MainActor final class Orbit: ObservableObject {
    static let shared = Orbit()
    @Published private(set) var ledger: OrbitLedger
    @Published var enabled: Bool {
        didSet {
            Store.settings.set(enabled, forKey: "orbit.enabled")
            heartbeat.reset()
            if !enabled { OrbitEngine.shared.pause() }
            configureTimer()
            persist()
        }
    }
    private var heartbeat = OrbitHeartbeat()
    private var timer: Timer?
    private var observers: [AnyCancellable] = []
    private var lastSave = Date()
    private let file = Store.file("orbit.json")

    private init() {
        enabled = Store.settings.bool(forKey: "orbit.enabled")
        ledger = Disk.read(Store.file("orbit.json")).flatMap { try? JSONDecoder().decode(OrbitLedger.self, from: $0) } ?? OrbitLedger()
        ledger.prune(now: Date())
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.heartbeat.reset() }
            }.store(in: &observers)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.heartbeat.reset(); self?.persist() }
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.persist(now: true) }
        }.store(in: &observers)
        configureTimer()
    }

    private func configureTimer() {
        timer?.invalidate(); timer = nil
        guard enabled, !Store.testing else { return }
        sample()
        let made = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        made.tolerance = 1
        RunLoop.main.add(made, forMode: .common)
        timer = made
    }

    private func sample() {
        var site: OrbitLedger.Site?
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        if enabled, NSApp.isActive,
           let browser = Browsers.browser(for: NSApp.keyWindow), !browser.isPopup, !browser.welcoming,
           let tab = browser.active, tab.page == nil, !tab.asleep,
           idle < 180 || (tab.noisy && !tab.muted) {
            site = OrbitLedger.Site(profile: browser.profileID, url: tab.pageAddress, privateTab: tab.shy, audible: tab.noisy && !tab.muted)
        }
        heartbeat.sample(at: Date(), site: site, into: &ledger)
        if let site { OrbitEngine.shared.heartbeat(site) } else { OrbitEngine.shared.pause() }
        if Date().timeIntervalSince(lastSave) >= 60 { persist() }
    }

    private func persist(now: Bool = false) {
        ledger.prune(now: Date())
        let snapshot = ledger
        Disk.write(file, now: now) { try? JSONEncoder().encode(snapshot) }
        lastSave = Date()
    }

    func clear(profile: UUID) {
        heartbeat.reset()
        ledger.clear(profile: profile)
        persist(now: true)
    }

    func rows(profile: UUID, days: Int) -> [OrbitLedger.Entry] {
        let start = Calendar.current.date(byAdding: .day, value: 1 - days, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return ledger.rows(profile: profile, since: start)
    }

    func export(profile: UUID, days: Int) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Moon-Orbit.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = rows(profile: profile, days: days)
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(data).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            let alert = NSAlert(error: error); alert.runModal()
        }
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds >= 0, let minutes = Int(exactly: (seconds / 60).rounded(.down)) else { return "—" }
        if minutes == 0 { return seconds > 0 ? "< 1 min" : "0 min" }
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    static func sites(_ rows: [OrbitLedger.Entry]) -> [(host: String, seconds: Double)] {
        Dictionary(grouping: rows, by: \.host).map { (host: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }
            .sorted { $0.seconds == $1.seconds ? $0.host < $1.host : $0.seconds > $1.seconds }
    }
}

struct OrbitDoor: View {
    @ObservedObject var browser: Browser
    var body: some View {
        Door(icon: "sparkles", on: browser.orbitOpen, help: "Orbit — Activity") {
            Nebula.shared.suspend(in: browser)
            browser.orbitOpen.toggle()
        }
            .accessibilityLabel("Orbit Activity")
            .accessibilityIdentifier("orbit.door")
    }
}

/// The largest rectangle the card can occupy, in window coordinates.
/// Prefer the space beside the dock, overlapping the column only when needed.
enum OrbitSummaryLayout {
    static func available(in size: CGSize, sidebarWidth: CGFloat, onRight: Bool) -> CGRect {
        let margin: CGFloat = 10
        let width = min(320, max(0, size.width - 2 * margin))
        let height = max(0, size.height - 2 * margin)
        let inset = max(margin, min(sidebarWidth + margin, size.width - width - margin))
        return CGRect(x: onRight ? size.width - inset - width : inset, y: margin,
                      width: width, height: height)
    }
}

struct OrbitSummaryOverlay: View {
    @ObservedObject var browser: Browser
    let sidebarWidth: CGFloat
    let onRight: Bool

    var body: some View {
        GeometryReader { geometry in
            let area = OrbitSummaryLayout.available(in: geometry.size, sidebarWidth: sidebarWidth, onRight: onRight)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { browser.orbitOpen = false }
                    .accessibilityHidden(true)
                OrbitSummary(orbit: .shared, profile: browser.profileID, close: { browser.orbitOpen = false }) {
                    browser.orbitOpen = false
                    browser.show(InternalPage(.orbit))
                }
                .frame(width: area.width)
                .frame(height: area.height, alignment: .bottom)
                .offset(x: area.minX, y: area.minY)
            }
        }
        .clipped()
    }
}

private struct OrbitSummary: View {
    @ObservedObject var orbit: Orbit
    let profile: UUID
    let close: () -> Void
    let more: () -> Void
    @ObservedObject private var engine = OrbitEngine.shared
    private var rows: [OrbitLedger.Entry] { orbit.rows(profile: profile, days: 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Orbit", systemImage: "sparkles").font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle("Track activity", isOn: $orbit.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .help("Track website time on this Mac")
                Button(action: close) {
                    Label("Close Orbit summary", systemImage: "xmark").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }
            ViewThatFits(in: .vertical) {
                activity.fixedSize(horizontal: false, vertical: true)
                ScrollView { activity }
            }
            Divider()
            Button(action: more) { HStack { Text("See more"); Spacer(); Image(systemName: "chevron.right") } }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).accessibilityIdentifier("orbit.more")
        }
        .padding(14)
        .popoverGround(card: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orbit.summary")
        .task { if engine.enabled { engine.refresh() } }
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Orbit.duration(rows.reduce(0) { $0 + $1.seconds })).font(.system(size: 29, weight: .medium, design: .rounded))
                Text("today").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text(orbit.enabled ? "Your first websites will appear here as you browse." : "Turn on Orbit to see where your browsing time goes.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                OrbitSites(rows: Array(Orbit.sites(rows).prefix(4)), showsFavicons: true)
            }
            Divider()
            if engine.enabled {
                HStack {
                    Image(systemName: engine.connected ? "checkmark.circle" : "circle.dotted")
                    Text(engine.connected ? "Mac active time: \(Orbit.duration(engine.activeSeconds))" : engine.status)
                        .lineLimit(2)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Local to this Mac. Website names and time only. Private tabs excluded. Pauses in the background or after three minutes idle, unless the page is playing audio.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct OrbitSites: View {
    let rows: [(host: String, seconds: Double)]
    var showsFavicons = false
    private var peak: Double { max(1, rows.first?.seconds ?? 1) }
    var body: some View {
        VStack(spacing: 13) {
            ForEach(rows, id: \.host) { row in
                VStack(spacing: 6) {
                    HStack {
                        if showsFavicons {
                            Mark(icon: Favicons.shared.cached(row.host), letter: String(row.host.prefix(1)).uppercased())
                                .accessibilityHidden(true)
                        }
                        Text(row.host).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Orbit.duration(row.seconds)).foregroundStyle(.secondary).monospacedDigit()
                    }.font(.system(size: 12))
                    GeometryReader { proxy in
                        Capsule().fill(.primary.opacity(0.06))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor.opacity(0.65)).frame(width: max(3, proxy.size.width * row.seconds / peak))
                            }
                    }.frame(height: 4).accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct OrbitMoonDetail: View {
    @ObservedObject var orbit: Orbit
    let profile: UUID
    @State private var days = 1
    @State private var clearing = false
    private var rows: [OrbitLedger.Entry] { orbit.rows(profile: profile, days: days) }
    private var sites: [(host: String, seconds: Double)] { Orbit.sites(rows) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Orbit", systemImage: "sparkles").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Activity · \(Profiles.shared.profile(profile).name)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Tracking", isOn: $orbit.enabled).toggleStyle(.switch).controlSize(.small)
            }.padding(24)
            Picker("Period", selection: $days) {
                Text("Today").tag(1); Text("7 days").tag(7); Text("30 days").tag(30)
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 48) {
                        metric("Active browsing", Orbit.duration(rows.reduce(0) { $0 + $1.seconds }))
                        metric("Websites", "\(sites.count)")
                    }
                    if rows.isEmpty {
                        ContentUnavailableView(orbit.enabled ? "A little space to begin" : "Orbit is paused",
                                               systemImage: "moon.stars", description: Text("Enable tracking and browse in Moon to build your activity breakdown."))
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(days == 1 ? "By hour" : "By day").font(.system(size: 13, weight: .semibold))
                            timeline
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Websites").font(.system(size: 13, weight: .semibold))
                            OrbitSites(rows: sites, showsFavicons: true)
                        }
                    }
                    Text("Only the foreground website in this profile is counted. Private tabs, Moon’s internal pages, other apps and long idle periods are excluded. Orbit stores website names and hourly totals for 30 days, never full URLs, searches, page titles, passwords or page content.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            Divider()
            HStack {
                Button("Clear activity…", role: .destructive) { clearing = true }.disabled(orbit.rows(profile: profile, days: 30).isEmpty)
                Spacer()
                Button("Export JSON…") { orbit.export(profile: profile, days: days) }.disabled(rows.isEmpty)
            }.controlSize(.small).padding(18)
        }
        .background(.background)
        .confirmationDialog("Clear Orbit activity for this profile?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Clear activity", role: .destructive) { orbit.clear(profile: profile) }
        } message: { Text("This removes all recorded website time for this profile from this Mac.") }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }

    private var timeline: some View {
        let calendar = Calendar.current
        let count = days == 1 ? 24 : days
        let start = calendar.date(byAdding: .day, value: 1 - days, to: calendar.startOfDay(for: Date())) ?? Date()
        let totals = (0..<count).map { index -> Double in
            guard let from = calendar.date(byAdding: days == 1 ? .hour : .day, value: index, to: start),
                  let until = calendar.date(byAdding: days == 1 ? .hour : .day, value: 1, to: from) else { return 0 }
            return rows.filter { $0.hour >= from && $0.hour < until }.reduce(0) { $0 + $1.seconds }
        }
        let peak = max(1, totals.max() ?? 1)
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3).fill(Color.accentColor.opacity(totals[index] > 0 ? 0.65 : 0.08))
                        .frame(height: max(3, 80 * totals[index] / peak))
                        .help("\(days == 1 ? "Hour \(index)" : "Day \(index + 1)"): \(Orbit.duration(totals[index]))")
                }
            }.frame(height: 80)
            HStack {
                Text(days == 1 ? "00:00" : start.formatted(date: .abbreviated, time: .omitted))
                Spacer(); Text(days == 1 ? "23:00" : "Today")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 1 ? "Hourly activity" : "Daily activity")
        .accessibilityValue(totals.enumerated().map { "\($0.offset): \(Orbit.duration($0.element))" }.joined(separator: ", "))
    }
}

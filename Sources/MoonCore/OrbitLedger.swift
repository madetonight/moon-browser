import Foundation

/// Orbit keeps time by website and hour, never page paths, queries or titles.
public struct OrbitLedger: Codable, Equatable, Sendable {
    public struct Site: Equatable, Sendable {
        public let profile: UUID
        public let host: String
        public let origin: String
        public let audible: Bool
        public init?(profile: UUID, url: URL?, privateTab: Bool, audible: Bool = false) {
            guard !privateTab, let url, ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
            self.profile = profile
            self.audible = audible
            self.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            var clean = URLComponents()
            clean.scheme = url.scheme?.lowercased(); clean.host = host
            clean.path = "/"
            self.origin = clean.string ?? "https://\(self.host)/"
        }
    }

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public let profile: UUID
        public let host: String
        public let hour: Date
        public var seconds: Double
        public var id: String { "\(profile)|\(host)|\(hour.timeIntervalSince1970)" }
    }

    public private(set) var entries: [Entry] = []
    public init() {}

    /// Small, bounded heartbeats cannot count sleep or time in another app.
    public mutating func add(site: Site, from start: Date, to end: Date, calendar: Calendar = .current) {
        guard end > start, end.timeIntervalSince(start) <= 12 else { return }
        var cursor = start
        while cursor < end {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor), hour.end > cursor else { break }
            let until = min(end, hour.end)
            let seconds = until.timeIntervalSince(cursor)
            if let at = entries.firstIndex(where: { $0.profile == site.profile && $0.host == site.host && $0.hour == hour.start }) {
                entries[at].seconds += seconds
            } else if entries.count < 60_000 {
                entries.append(Entry(profile: site.profile, host: site.host, hour: hour.start, seconds: seconds))
            }
            cursor = until
        }
    }

    public mutating func prune(now: Date, calendar: Calendar = .current) {
        let cutoff = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        entries.removeAll { $0.hour < cutoff || $0.hour > now || !$0.seconds.isFinite || $0.seconds <= 0 }
    }

    public mutating func clear(profile: UUID) { entries.removeAll { $0.profile == profile } }
    public func rows(profile: UUID, since: Date) -> [Entry] {
        entries.filter { $0.profile == profile && $0.hour >= since }
    }
}

/// A change of site, focus, privacy or clock drops the uncertain interval.
public struct OrbitHeartbeat: Sendable {
    private var previous: (Date, OrbitLedger.Site)?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func sample(at date: Date, site: OrbitLedger.Site?, into ledger: inout OrbitLedger, calendar: Calendar = .current) {
        defer { previous = site.map { (date, $0) } }
        guard let site, let (start, before) = previous, before == site else { return }
        ledger.add(site: site, from: start, to: date, calendar: calendar)
    }
}

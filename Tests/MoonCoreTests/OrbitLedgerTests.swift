import Foundation
import Testing
@testable import MoonCore

private let orbitProfile = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
private var orbitCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}
private func orbitSite(_ host: String = "example.com", profile: UUID = orbitProfile) -> OrbitLedger.Site {
    OrbitLedger.Site(profile: profile, url: URL(string: "https://\(host)/private/path?token=secret#fragment"), privateTab: false)!
}

@Test func orbitExcludesPrivateAndNonWebsitePages() throws {
    for text in ["moon://passwords", "file:///private/secret.txt", "about:blank", "data:text/html,secret"] {
        #expect(OrbitLedger.Site(profile: orbitProfile, url: URL(string: text), privateTab: false) == nil)
    }
    #expect(OrbitLedger.Site(profile: orbitProfile, url: URL(string: "https://example.com"), privateTab: true) == nil)
    let site = orbitSite("www.example.com")
    #expect(site.host == "example.com")
    var ledger = OrbitLedger()
    ledger.add(site: site, from: Date(timeIntervalSince1970: 1_700_000_000), to: Date(timeIntervalSince1970: 1_700_000_005))
    let json = String(decoding: try JSONEncoder().encode(ledger), as: UTF8.self)
    #expect(!json.contains("secret"))
    #expect(!json.contains("private/path"))
    #expect(!json.contains("https"))
    #expect(try JSONDecoder().decode(OrbitLedger.self, from: Data(json.utf8)) == ledger)
}

@Test func orbitHeartbeatDropsInactiveAndChangedSiteIntervals() {
    var ledger = OrbitLedger(); var beat = OrbitHeartbeat()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    beat.sample(at: now, site: orbitSite(), into: &ledger)
    beat.sample(at: now.addingTimeInterval(5), site: orbitSite(), into: &ledger)
    beat.sample(at: now.addingTimeInterval(10), site: nil, into: &ledger)
    beat.sample(at: now.addingTimeInterval(15), site: orbitSite(), into: &ledger)
    beat.sample(at: now.addingTimeInterval(20), site: orbitSite("other.com"), into: &ledger)
    beat.sample(at: now.addingTimeInterval(25), site: orbitSite("other.com"), into: &ledger)
    #expect(ledger.entries.reduce(0) { $0 + $1.seconds } == 10)
    #expect(ledger.entries.count == 2)
}

@Test func orbitNeverCountsSleepClockChangesOrResetTime() {
    var ledger = OrbitLedger(); var beat = OrbitHeartbeat()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    beat.sample(at: now, site: orbitSite(), into: &ledger)
    beat.sample(at: now.addingTimeInterval(3600), site: orbitSite(), into: &ledger)
    beat.sample(at: now, site: orbitSite(), into: &ledger)
    beat.reset()
    beat.sample(at: now.addingTimeInterval(5), site: orbitSite(), into: &ledger)
    #expect(ledger.entries.isEmpty)
}

@Test func orbitSplitsTimeAcrossMidnightAndHours() {
    let end = orbitCalendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 0, minute: 0, second: 3))!
    var ledger = OrbitLedger()
    ledger.add(site: orbitSite(), from: end.addingTimeInterval(-5), to: end, calendar: orbitCalendar)
    #expect(ledger.entries.map(\.seconds) == [2, 3])
    #expect(ledger.rows(profile: orbitProfile, since: orbitCalendar.startOfDay(for: end)).reduce(0) { $0 + $1.seconds } == 3)
}

@Test func orbitProfilesAreSeparatedAndClearedIndependently() {
    let other = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var ledger = OrbitLedger()
    for site in [orbitSite(), orbitSite(profile: other)] {
        ledger.add(site: site, from: now, to: now.addingTimeInterval(5))
    }
    #expect(ledger.rows(profile: orbitProfile, since: .distantPast).count == 1)
    ledger.clear(profile: orbitProfile)
    #expect(ledger.rows(profile: orbitProfile, since: .distantPast).isEmpty)
    #expect(ledger.rows(profile: other, since: .distantPast).count == 1)
}

@Test func orbitRetentionKeepsThirtyCalendarDays() {
    let now = orbitCalendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
    var ledger = OrbitLedger()
    for days in [0, 29, 30] {
        let start = orbitCalendar.date(byAdding: .day, value: -days, to: now)!
        ledger.add(site: orbitSite(), from: start, to: start.addingTimeInterval(5), calendar: orbitCalendar)
    }
    ledger.prune(now: now.addingTimeInterval(10), calendar: orbitCalendar)
    #expect(ledger.entries.count == 2)
}

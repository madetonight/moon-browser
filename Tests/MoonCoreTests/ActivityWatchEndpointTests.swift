import Foundation
import Testing
@testable import MoonCore

@Test func activityWatchIsRestrictedToItsExactLoopbackOrigin() {
    #expect(ActivityWatchEndpoint.allows(URL(string: "http://127.0.0.1:5600/api/0/info")!))
    for address in ["https://127.0.0.1:5600/", "http://127.0.0.1:5601/", "http://localhost:5600/",
                    "http://127.0.0.1.evil.test:5600/", "http://127.0.0.1:5600@evil.test/",
                    "http://secret@127.0.0.1:5600/", "file:///etc/passwd", "https://example.com/"] {
        #expect(!ActivityWatchEndpoint.allows(URL(string: address)!))
    }
}

@Test func activityWatchRoutesAndBucketNamesRemainData() throws {
    let id = "watcher_\"; RETURN = query_bucket('private'); //"
    let literal = ActivityWatchEndpoint.literal(id)
    #expect(try JSONDecoder().decode(String.self, from: Data(literal.utf8)) == id)
    let route = ActivityWatchEndpoint.workspace("/settings/privacy")
    #expect(ActivityWatchEndpoint.allows(route))
    #expect(route.fragment == "/settings/privacy")
    #expect(ActivityWatchEndpoint.allows(ActivityWatchEndpoint.api(["buckets", "moon/profile"])) )
}

@Test func orbitEngineOriginNeverIncludesUserSecrets() {
    let site = OrbitLedger.Site(profile: UUID(), url: URL(string: "http://person:password@www.example.com/path?token=secret#private"), privateTab: false)!
    #expect(site.origin == "http://www.example.com/")
    #expect(!site.origin.contains("password"))
    #expect(!site.origin.contains("secret"))
}

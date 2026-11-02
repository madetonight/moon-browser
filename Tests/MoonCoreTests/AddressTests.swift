import Foundation
import Testing
@testable import MoonCore

@Test func addressesAndSearches() {
    #expect(Address.resolve(" example.com ")?.absoluteString == "https://example.com")
    #expect(Address.resolve("10.io")?.scheme == "https")
    #expect(Address.resolve("192.168.example.com")?.scheme == "https")
    #expect(Address.resolve("localhost:8000")?.absoluteString == "http://localhost:8000")
    #expect(Address.resolve("192.168.1.2:3000")?.scheme == "http")
    #expect(Address.resolve("moon browser")?.host == "duckduckgo.com")
    #expect(Address.resolve("hello@example.com")?.host == "duckduckgo.com")
    #expect(Address.resolve("javascript:alert(1)")?.host == "duckduckgo.com")
    #expect(Address.resolve(" ") == nil)
}
@Test func searchEncodingCannotAddParameters() {
    let url = SearchEngine.google.search("coffee & tea #one + two?你好")
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    #expect(parts?.queryItems?.count == 1)
    #expect(parts?.queryItems?.first?.value == "coffee & tea #one + two?你好")
    #expect(parts?.fragment == nil)
}
@Test func cleanLinksPreserveMeaningfulParameters() {
    let url = URL(string: "https://example.com/watch?v=abc&utm_source=test&fbclid=track#part")!
    #expect(Address.clean(url).absoluteString == "https://example.com/watch?v=abc#part")
}
@Test func localAddressesAreActuallyNumeric() {
    #expect(Address.isLocalHost("10.0.0.1"))
    #expect(Address.isLocalHost("172.16.0.1"))
    #expect(!Address.isLocalHost("172.32.0.1"))
    #expect(!Address.isLocalHost("10.example.com"))
    #expect(!Address.isLocalHost("192.168.1.999"))
}
@Test func bookmarksEscapeUntrustedHTML() {
    let html = BookmarkDocument.export([PageRecord(title: "<script>bad</script>", url: URL(string: "https://example.com/?a=1&b=2")!)])
    #expect(!html.contains("<script>"))
    #expect(html.contains("&lt;script&gt;"))
    #expect(html.contains("&amp;b=2"))
}
@Test func libraryRoundTrip() throws {
    var library = LibraryRecord()
    library.bookmarks = [PageRecord(title: "Test", url: URL(string: "https://example.com")!)]
    library.hiddenSelectors = ["example.com": ["#banner"]]
    library.unblockedHosts = ["example.org"]
    let decoded = try JSONDecoder().decode(LibraryRecord.self, from: JSONEncoder().encode(library))
    #expect(decoded.bookmarks == library.bookmarks)
    #expect(decoded.hiddenSelectors == library.hiddenSelectors)
    #expect(decoded.unblockedHosts == library.unblockedHosts)
}

import Foundation
import Testing
@testable import MoonCore

@Test func remoteSuggestionsRequireConsentAndProtectPrivateInput() {
    #expect(!SuggestionPolicy.permits("weather tomorrow", enabled: false, privateMode: false))
    #expect(!SuggestionPolicy.permits("weather tomorrow", enabled: true, privateMode: true))
    #expect(SuggestionPolicy.permits("weather tomorrow", enabled: true, privateMode: false))
    for input in ["https://example.com/token", "localhost:8080", "example.com", "/Users/me/file", "~/Documents", "../notes", "hello@example.com", "secret aBcDeFgH12345678", "account 123456789", "two\nlines"] {
        #expect(!SuggestionPolicy.permits(input, enabled: true, privateMode: false), "Must stay local: \(input)")
    }
}

@Test func suggestionURLsPreserveQueriesWithoutAddingParameters() throws {
    for engine in SearchEngine.allCases {
        let query = "café & tea + milk? #1"
        let url = try #require(SuggestionPolicy.endpoint(query: query, engine: engine))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https")
        #expect(parts.fragment == nil)
        #expect(parts.queryItems?.last?.value == query)
        #expect(parts.queryItems?.filter { $0.value == query }.count == 1)
    }
}

@Test func malformedSuggestionResponsesCannotBecomeOffers() {
    #expect(SuggestionPolicy.parse(Data("{\"error\":\"bad\"}".utf8), query: "moon").isEmpty)
    #expect(SuggestionPolicy.parse(Data("[\"moon\",[123]]".utf8), query: "moon").isEmpty)
    let data = Data("[\"moon\",[\"Moon\",\"moon browser\",\" MOON BROWSER \",\"\",\"moon phase\",\"moon rise\",\"moon set\",\"extra\"]]".utf8)
    #expect(SuggestionPolicy.parse(data, query: "moon") == ["moon browser", "moon phase", "moon rise", "moon set"])
}

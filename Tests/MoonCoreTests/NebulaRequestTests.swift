import Foundation
import Testing
@testable import MoonCore

struct NebulaRequestTests {
    @Test(arguments: [
        ("take me to YouTube", "https://www.youtube.com"),
        ("Could you please open YouTube.", "https://www.youtube.com"),
        ("Hey Nebula, can you please go to Google.", "https://www.google.com"),
        ("Open GitHub, please.", "https://github.com"),
        ("visit you tube", "https://www.youtube.com"),
        ("go to example dot com", "https://example.com"),
        ("youtube", "https://www.youtube.com"),
        ("https://example.com/CaseSensitive", "https://example.com/CaseSensitive")
    ])
    func conversationalNavigation(input: String, destination: String) throws {
        #expect(NebulaRequest.resolve(input) == .command(.open(try #require(URL(string: destination)))))
    }

    @Test(arguments: [
        ("Lloyd Television guitarist", "Lloyd Television guitarist"),
        ("Who played guitar in Television?", "Who played guitar in Television?"),
        ("Look up Richard Lloyd.", "Richard Lloyd"),
        ("Find Richard Lloyd guitar videos", "Richard Lloyd guitar videos"),
        ("open an unfamiliar website", "an unfamiliar website"),
        ("Do not close my tabs", "Do not close my tabs")
    ])
    func unknownSpeechGetsUsefulSearchInsteadOfAGuessedAction(input: String, query: String) {
        #expect(NebulaRequest.resolve(input) == .googleSearch(query))
        let url = NebulaRequest.googleURL(for: query)
        #expect(url?.host == "www.google.com")
        #expect(url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first?.value } == query)
    }

    @Test(arguments: ["open file:///etc/passwd", "visit javascript:alert(1)",
                      "https://user:secret@example.com", "open ~/Documents/private", "/etc/passwd"])
    func unsafeAddressesAreNotOpenedOrSentToSearch(input: String) {
        #expect(NebulaRequest.resolve(input) == .unsupportedAddress)
    }

    @Test func boundedInputAndNativeConfirmationPaths() {
        #expect(NebulaRequest.resolve("...") == nil)
        #expect(NebulaRequest.resolve(String(repeating: "x", count: 2_001)) == nil)
        #expect(NebulaRequest.resolve("Please close all my YouTube tabs.") == .command(.closeMatching("youtube")))
        #expect(NebulaRequest.resolve("Please open a new tab.") == .command(.newTab))
    }
}

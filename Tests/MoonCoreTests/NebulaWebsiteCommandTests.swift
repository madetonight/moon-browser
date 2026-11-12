import Foundation
import Testing
@testable import MoonCore

struct NebulaWebsiteCommandTests {
    @Test(arguments: [
        ("Open YouTube", "https://www.youtube.com"),
        ("Open YouTube.", "https://www.youtube.com"),
        ("  Open YouTube.  ", "https://www.youtube.com"),
        ("Open You Tube.", "https://www.youtube.com"),
        ("Open YouTube!", "https://www.youtube.com"),
        ("Open Gmail.", "https://mail.google.com"),
        ("Open X.", "https://x.com"),
        ("open youtube.com.", "https://youtube.com"),
        ("open https://youtube.com.", "https://youtube.com"),
        ("open https://example.com./Watch?title=CaseSensitive.#Section", "https://example.com/Watch?title=CaseSensitive.#Section"),
        ("open https://example.com/notes.", "https://example.com/notes.")
    ])
    func spokenWebsiteResolvesWithoutSentenceDot(input: String, destination: String) throws {
        let url = try #require(URL(string: destination))
        #expect(NebulaCommand.parse(input) == .open(url))
    }

    @Test(arguments: ["open .", "open unknown.", "open example..com.", "open .example.com",
                      "open https://user:secret@example.com.", "open file:///etc/passwd.",
                      "open javascript:alert(1)."])
    func punctuationCannotBypassDestinationChecks(input: String) {
        #expect(NebulaCommand.parse(input) == nil)
    }
}

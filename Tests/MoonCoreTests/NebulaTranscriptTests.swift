import Foundation
import Testing
@testable import MoonCore

struct NebulaTranscriptTests {
    @Test(arguments: [
        ("Open YouTube.", "Open YouTube"),
        ("youtube.com.", "youtube.com"),
        ("  youtube.com. \n", "youtube.com"),
        ("youtube.com...", "youtube.com"),
        ("youtube.com. .", "youtube.com"),
        ("youtube.com。", "youtube.com"),
        ("youtube.com．", "youtube.com"),
        ("youtube.com…", "youtube.com"),
        ("First sentence. Second sentence.", "First sentence. Second sentence"),
        ("Version 3.14.", "Version 3.14"),
        (".config.", ".config"),
        ("How does this work?", "How does this work?"),
        ("https://example.com/notes.", "https://example.com/notes"),
        ("https://example.com/file%2E", "https://example.com/file%2E"),
        ("...", ""),
        ("", "")
    ])
    func recognizedSpeechHasNoFinalPeriod(input: String, expected: String) {
        #expect(NebulaTranscript.withoutTrailingPeriod(input) == expected)
    }

    @Test(arguments: [
        ("Search for YouTube.", NebulaCommand.search("YouTube")),
        ("Open YouTube.", .open(URL(string: "https://www.youtube.com")!)),
        ("Open https://example.com/notes.", .open(URL(string: "https://example.com/notes")!))
    ])
    func commandReceivesTheCleanedSpeech(input: String, expected: NebulaCommand) {
        #expect(NebulaCommand.parse(NebulaTranscript.withoutTrailingPeriod(input)) == expected)
    }
}

import Foundation

/// Resolve speech without guessing destructive actions or rewriting names.
public enum NebulaRequest: Equatable, Sendable {
    case command(NebulaCommand)
    case googleSearch(String)
    case unsupportedAddress

    public static func resolve(_ speech: String) -> Self? {
        var text = NebulaTranscript.withoutTrailingPeriod(speech)
        guard !text.isEmpty, text.count <= 2_000 else { return nil }
        for _ in 0..<3 {
            let cleaned = text.replacingOccurrences(
                of: #"^(?:(?:hey\s+)?nebula[,\s]+|(?:can|could|would)\s+you\s+(?:please\s+)?|please\s+)"#,
                with: "", options: [.regularExpression, .caseInsensitive])
            if cleaned == text { break }
            text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.replacingOccurrences(of: #"[,\s]+please[.!?]?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard !text.isEmpty else { return nil }
        if let command = NebulaCommand.parse(text) { return .command(command) }

        let lower = text.lowercased()
        for prefix in ["take me to ", "navigate to ", "go to ", "visit ", "launch ", "open "] where lower.hasPrefix(prefix) {
            let destination = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !destination.isEmpty else { return nil }
            let spokenAddress = destination.replacingOccurrences(of: #"\s+dot\s+"#, with: ".", options: [.regularExpression, .caseInsensitive])
            if let command = NebulaCommand.parse("open " + spokenAddress) { return .command(command) }
            if unsafeAddress(spokenAddress) { return .unsupportedAddress }
            return .googleSearch(destination)
        }
        for prefix in ["look up ", "google ", "find ", "show me "] where lower.hasPrefix(prefix) {
            let query = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? nil : .googleSearch(query)
        }
        if let command = NebulaCommand.parse("open " + text) { return .command(command) }
        if unsafeAddress(text) { return .unsupportedAddress }
        return .googleSearch(text)
    }

    private static func unsafeAddress(_ text: String) -> Bool {
        text.range(of: #"^(?:[A-Za-z][A-Za-z0-9+.-]*:|/|~[/\\])"#, options: .regularExpression) != nil
            || text.contains("@")
    }

    public static func googleURL(for query: String) -> URL? {
        guard !query.isEmpty, query.count <= 2_000 else { return nil }
        var parts = URLComponents(string: "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts.url
    }
}

import Foundation

/// Choose from context, without a Control/Dictate mode switch. A recognized
/// browser action wins; ordinary words go into the explicitly focused field.
public enum NebulaIntent {
    private static let dictationPrefixes = ["type ", "write ", "dictate ", "escribe ", "dicta "]
    private static let actionPrefixes = ["open ", "go to ", "take me to ", "navigate to ", "visit ", "launch ",
        "search ", "look up ", "google ", "find ", "show me ", "abre ", "abrir ", "ve a ", "busca ",
        "buscar ", "busca en google ", "muestrame ", "llevame a "]

    public static func shouldDictate(_ text: String) -> Bool {
        let lower = text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        if dictationPrefixes.contains(where: lower.hasPrefix) { return true }
        if case .command = NebulaRequest.resolve(text) { return false }
        return !actionPrefixes.contains(where: lower.hasPrefix)
    }
    public static func dictationText(_ text: String) -> String {
        let clean = NebulaTranscript.withoutTrailingPeriod(text)
        if let prefix = dictationPrefixes.first(where: clean.lowercased().hasPrefix) {
            return String(clean.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean
    }
}

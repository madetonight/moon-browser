import Foundation

/// Clean recognized speech before showing it or inserting it into a field.
public enum NebulaTranscript {
    public static func withoutTrailingPeriod(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.reversed().drop(while: {
            $0.isWhitespace || $0 == "." || $0 == "。" || $0 == "．" || $0 == "…"
        }).reversed())
    }
}

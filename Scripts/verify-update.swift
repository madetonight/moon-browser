import Foundation
import CryptoKit

// Public-key verification only. Feed authentication itself is checked by the
// pinned Sparkle verifier; this independently checks the archive and its entry.
struct InvalidUpdate: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw InvalidUpdate(message: message) }
}
final class Feed: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []
    private var item: [String: String]?
    private var field = ""
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        field = name
        if name == "item" { item = [:] }
        if name == "enclosure" { item?.merge(attributes) { _, new in new } }
    }
    func parser(_ parser: XMLParser, foundCharacters text: String) {
        if ["sparkle:version", "sparkle:shortVersionString", "sparkle:minimumSystemVersion"].contains(field) {
            item?[field, default: ""] += text
        }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "item", let item { items.append(item); self.item = nil }
        field = ""
    }
}
func checked(_ bytes: Data, name: String, feed: Data, info: [String: Any], prefix: String) throws {
    try require(!bytes.isEmpty && bytes.count <= 128 * 1024 * 1024 && feed.count <= 16 * 1024 * 1024, "Update files exceed verification limits")
    try require(info["MoonUpdateFeedReady"] as? Bool == true && info["SURequireSignedFeed"] as? Bool == true
        && info["SUVerifyUpdateBeforeExtraction"] as? Bool == true && info["SUSignedFeedFailureExpirationInterval"] as? Int == 0,
        "Candidate update protections are not enabled")
    guard let base = URLComponents(string: prefix), base.scheme == "https", base.host != nil,
          base.percentEncodedUser == nil, base.percentEncodedPassword == nil,
          base.query == nil, base.fragment == nil, prefix.hasSuffix("/") else { throw InvalidUpdate(message: "Invalid archive prefix") }
    guard let encoded = info["SUPublicEDKey"] as? String, let rawKey = Data(base64Encoded: encoded), rawKey.count == 32 else {
        throw InvalidUpdate(message: "Missing public verification key")
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
    let delegate = Feed(), parser = XMLParser(data: feed)
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    try require(parser.parse(), "Malformed appcast")
    let matching = delegate.items.filter { $0["url"] == prefix + name }
    try require(matching.count == 1, "Expected exactly one matching archive entry")
    let entry = matching[0]
    try require(entry["sparkle:version"]?.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleVersion"] as? String
        && entry["sparkle:shortVersionString"]?.trimmingCharacters(in: .whitespacesAndNewlines) == info["CFBundleShortVersionString"] as? String,
        "Appcast version/build do not match the candidate")
    func system(_ value: String?) -> [Int]? {
        guard let value else { return nil }
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let values = parts.compactMap { Int($0) }
        return values.count == parts.count ? values + Array(repeating: 0, count: 3 - values.count) : nil
    }
    guard let minimum = system(info["LSMinimumSystemVersion"] as? String), system(entry["sparkle:minimumSystemVersion"]) == minimum else {
        throw InvalidUpdate(message: "Appcast minimum macOS does not match")
    }
    try require(Int(entry["length"] ?? "") == bytes.count, "Archive length mismatch")
    guard let signature = Data(base64Encoded: entry["sparkle:edSignature"] ?? ""), key.isValidSignature(signature, for: bytes) else {
        throw InvalidUpdate(message: "Archive Ed25519 signature is invalid")
    }
    var altered = bytes; altered[0] ^= 1
    try require(!key.isValidSignature(signature, for: altered), "Altered archive unexpectedly accepted")
}

do {
    if CommandLine.arguments.dropFirst() == ["--self-test"] {
        let key = Curve25519.Signing.PrivateKey(), bytes = Data("Harmless archive fixture".utf8)
        let signature = try key.signature(for: bytes).base64EncodedString()
        let prefix = "https://example.test/releases/", name = "Moon-fixture-arm64.zip"
        let xml = "<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel><item><sparkle:version>1</sparkle:version><sparkle:shortVersionString>0.1</sparkle:shortVersionString><sparkle:minimumSystemVersion>26.0.0</sparkle:minimumSystemVersion><enclosure url=\"\(prefix + name)\" length=\"\(bytes.count)\" sparkle:edSignature=\"\(signature)\"/></item></channel></rss>"
        let info: [String: Any] = ["SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(), "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1", "LSMinimumSystemVersion": "26.0", "MoonUpdateFeedReady": true, "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true, "SUSignedFeedFailureExpirationInterval": 0]
        try checked(bytes, name: name, feed: Data(xml.utf8), info: info, prefix: prefix)
        let badFeeds = [xml.replacingOccurrences(of: ">1<", with: ">2<"), xml.replacingOccurrences(of: "length=\"\(bytes.count)\"", with: "length=\"1\""), xml.replacingOccurrences(of: prefix, with: "https://user:password@example.test/releases/"), xml.replacingOccurrences(of: "26.0.0", with: "25.0.0")]
        for invalid in badFeeds {
            var rejected = false
            do { try checked(bytes, name: name, feed: Data(invalid.utf8), info: info, prefix: prefix) } catch { rejected = true }
            try require(rejected, "Invalid feed was accepted")
        }
        var rejected = false
        do { try checked(bytes + Data([0]), name: name, feed: Data(xml.utf8), info: info, prefix: prefix) } catch { rejected = true }
        try require(rejected, "Changed archive was accepted")
        var changed = bytes; changed[0] ^= 1
        rejected = false
        do { try checked(changed, name: name, feed: Data(xml.utf8), info: info, prefix: prefix) } catch { rejected = true }
        try require(rejected, "Same-length tampered archive was accepted")
        print("Seven public-key release verification controls passed; no Keychain access")
    } else {
        try require(CommandLine.arguments.count == 5, "Pass archive, appcast, candidate Info.plist and download prefix")
        let archive = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])), format: nil) as? [String: Any] else { throw InvalidUpdate(message: "Invalid candidate plist") }
        try checked(Data(contentsOf: archive), name: archive.lastPathComponent,
                    feed: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])), info: info, prefix: CommandLine.arguments[4])
        print("Verified archive signature, length, URL, version and minimum macOS with the bundled public key; altered bytes rejected")
    }
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}

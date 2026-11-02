import MoonCore
import Foundation
import CryptoKit
import Security

// Chrome extensions, straight from the Chrome Web Store.
//
// An extension there is a .crx: a zip with a signed header in front of it.
// It is fetched from the same public update address every Chromium browser
// asks, the header is checked, and the zip is unpacked into the app's own
// folder for WebKit to load.
//
// The check that matters: a Chrome extension's id is not a name anybody
// chose — it is the first sixteen bytes of the SHA-256 of its public key,
// written as letters a to p. So the header must carry a public key that
// hashes to the id that was asked for, and a signature by that key over the
// zip that came with it. A file that was altered on the way, or an
// extension passed off under another's id, fails one or the other.

enum Crx {
    enum Refused: LocalizedError {
        case notAnID, download(Int), empty, notCrx, unsignedOrWrong, unpack

        var errorDescription: String? {
            switch self {
            case .notAnID: return "That isn't a Chrome Web Store link or extension id"
            case .download(let code): return "The Chrome Web Store answered \(code)"
            case .empty: return "The Chrome Web Store has nothing for that id — it may have been taken down, or only exist for old versions of Chrome"
            case .notCrx: return "What came back isn't a Chrome extension"
            case .unsignedOrWrong: return "The extension's signature doesn't hold up"
            case .unpack: return "The extension couldn't be unpacked"
            }
        }
    }

    /// The version of Chrome the store is told it is talking to, and the one
    /// extensions see in navigator.userAgent (ExtensionShims). Some set a
    /// minimum; the store refuses to hand those to a browser that says it
    /// is older, and some turn a feature off below a version: 1Password
    /// opens its popup to unlock only from Chrome 149, so at 140 its button
    /// in a field did nothing while it was locked (#685). Kept at Chrome's
    /// stable version (156 on 24 Oct 2026); look again every few releases.
    static let chromeVersion = "156.0.0.0"

    /// The id Chrome gives a folder loaded unpacked, from its real path:
    /// native messaging hosts shipped for such a folder list this id. The
    /// manifest's "key" is ignored, as nothing checks it and store keys are
    /// public, so a folder could otherwise take any extension's id.
    static func unpackedID(for folder: URL) -> String {
        letters(Array(SHA256.hash(data: Data(realPath(of: folder).utf8)).prefix(16)))
    }

    /// Where a folder really is, every link on the way resolved.
    static func realPath(of folder: URL) -> String {
        realpath(folder.path, nil).map { real in defer { free(real) }; return String(cString: real) } ?? folder.standardizedFileURL.path
    }

    /// Thirty-two letters from a to p, wherever they are — a bare id, a store
    /// link, an old chrome.google.com/webstore link.
    static func id(in text: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "(?<![a-z])([a-p]{32})(?![a-z])")
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text.lowercased(), range: range),
              let found = Range(match.range(at: 1), in: text)
        else { return nil }
        return text[found].lowercased()
    }

    /// The extension a store page is about: the id in its /detail/ path
    /// and nowhere else — the listing the page shows is that one. Only on
    /// the store itself, over https, with nothing before its host.
    static func storeID(of url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else { return nil }
        let host = url.host()?.lowercased() ?? ""
        let pattern: String
        switch host {
        case "chromewebstore.google.com": pattern = #"^/detail/(?:[^/]+/)?([a-p]{32})(?:/.*)?$"#
        case "chrome.google.com": pattern = #"^/webstore/detail/(?:[^/]+/)?([a-p]{32})(?:/.*)?$"#
        default: return nil
        }
        let path = url.path
        guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let found = Range(match.range(at: 1), in: path)
        else { return nil }
        return String(path[found])
    }

    static func downloadURL(for id: String) -> URL {
        var parts = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        parts.queryItems = [
            URLQueryItem(name: "response", value: "redirect"),
            URLQueryItem(name: "prodversion", value: chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(id)&installsource=ondemand&uc"),
        ]
        return parts.url!
    }

    static func fetch(_ id: String) async throws -> Data {
        try await BoundedFetch.data(from: downloadURL(for: id), policy: .chromePackage, limit: ChromePackage.maximumBytes, timeout: 90)
    }

    /// The zip inside a CRX3, once its signature has been checked against
    /// `id`.
    static func verifiedZip(_ crx: Data, id: String) throws -> Data {
        try ChromePackage.verify(crx, expectedID: id).zip
    }

    /// Unpacks a zip into `folder`, which is replaced whole.
    static func unpack(_ zip: Data, into folder: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staged = folder.deletingLastPathComponent().appendingPathComponent(".moon-unpack-" + UUID().uuidString)
        defer { try? files.removeItem(at: staged) }
        try ExtensionArchive.extract(zip, to: staged)
        try ExtensionFiles.replace(staged, at: folder)
    }

    // MARK: - pieces

    private static func le32(_ b: [UInt8], _ at: Int) -> UInt32 {
        UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }

    /// The id's letters: each half-byte is a letter from a (0) to p (15).
    static func letters(_ bytes: [UInt8]) -> String {
        String(bytes.flatMap { [$0 >> 4, $0 & 0x0f] }.map { Character(UnicodeScalar(UInt8(97) + $0)) })
    }

    /// Length-delimited fields only, which is all a CRX header holds.
    private static func protobuf(_ b: [UInt8]) -> [(Int, [UInt8])] {
        var out: [(Int, [UInt8])] = []
        var i = 0
        func varint() -> Int? {
            var value = 0, shift = 0
            while i < b.count {
                let byte = Int(b[i]); i += 1
                value |= (byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
                if shift > 56 { return nil }
            }
            return nil
        }
        while i < b.count {
            guard let key = varint() else { break }
            let field = key >> 3, wire = key & 7
            switch wire {
            case 2:
                guard let length = varint(), i + length <= b.count else { return out }
                out.append((field, Array(b[i..<(i + length)])))
                i += length
            case 0: _ = varint()
            case 1: i += 8
            case 5: i += 4
            default: return out
            }
        }
        return out
    }

    /// An RSA public key as Chrome writes it (SubjectPublicKeyInfo DER),
    /// checked against a PKCS#1 v1.5 SHA-256 signature.
    private static func verify(rsaSPKI: Data, signature: Data, message: Data) -> Bool {
        var format = SecExternalFormat.formatOpenSSL
        var type = SecExternalItemType.itemTypePublicKey
        var items: CFArray?
        guard SecItemImport(rsaSPKI as CFData, nil, &format, &type, [], nil, nil, &items) == errSecSuccess,
              let key = (items as? [Any])?.first
        else { return false }
        return SecKeyVerifySignature(
            key as! SecKey, .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData, signature as CFData, nil
        )
    }
}

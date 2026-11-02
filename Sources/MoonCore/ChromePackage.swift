import CryptoKit
import Foundation
import Security

/// CRX3 framing/identity checks follow Chromium's public format, selectively
/// adapted from Search's Crx.swift under MIT (see THIRD_PARTY_NOTICES.md).
public enum ChromePackage {
    public static let maximumBytes = 32 * 1024 * 1024
    public struct Verified: Sendable {
        public let extensionID: String
        public let zip: Data
        public let algorithm: String
    }
    public enum Failure: String, Error, LocalizedError, Sendable {
        case invalidID, invalidHeader, signatureMismatch, oversized
        public var errorDescription: String? {
            switch self {
            case .invalidID: "Enter a Chrome Web Store link or a 32-letter extension ID."
            case .invalidHeader: "This is not a valid CRX3 extension package."
            case .signatureMismatch: "The extension's publisher signature or identity does not match."
            case .oversized: "The extension package exceeds Moon's 32 MiB download limit."
            }
        }
    }
    public static func extensionID(in text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if validID(text.lowercased()) { return text.lowercased() }
        guard let url = URL(string: text), url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return nil }
        let pieces = url.pathComponents.filter { $0 != "/" }
        let start: Int
        switch url.host?.lowercased() {
        case "chromewebstore.google.com": guard pieces.first == "detail" else { return nil }; start = 1
        case "chrome.google.com": guard pieces.prefix(2) == ["webstore", "detail"] else { return nil }; start = 2
        default: return nil
        }
        guard pieces.count == start + 1 || pieces.count == start + 2, let last = pieces.last, validID(last) else { return nil }
        return last
    }
    public static func downloadURL(for id: String) -> URL? {
        guard validID(id) else { return nil }
        var parts = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        // Client protocol version only; never used as a website User-Agent.
        parts.queryItems = [URLQueryItem(name: "response", value: "redirect"), URLQueryItem(name: "prodversion", value: "156.0.8078.48"), URLQueryItem(name: "acceptformat", value: "crx3"), URLQueryItem(name: "x", value: "id=\(id)&installsource=ondemand&uc")]
        return parts.url
    }
    public static func validID(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy { (97...112).contains($0) }
    }
    public static func id(forPublicKey key: Data) -> String { letters(Data(SHA256.hash(data: key).prefix(16))) }
    private static func letters(_ data: Data) -> String {
        String(decoding: data.flatMap { [UInt8(97) + ($0 >> 4), UInt8(97) + ($0 & 15)] }, as: UTF8.self)
    }
    public static func verify(_ input: Data, expectedID: String? = nil) throws -> Verified {
        guard input.count <= maximumBytes else { throw Failure.oversized }
        let bytes = BinaryBytes(input)
        guard input.count > 12, input.prefix(4).elementsEqual("Cr24".utf8), bytes.u32(4) == 3 else { throw Failure.invalidHeader }
        let headerLength = Int(bytes.u32(8))
        guard headerLength > 0, headerLength <= 1_048_576, headerLength < input.count - 12 else { throw Failure.invalidHeader }
        let fields = try protobuf(bytes.data(12..<(12 + headerLength)))
        let signed = try single(10000, in: fields)
        let identifierBytes = try single(1, in: protobuf(signed))
        guard identifierBytes.count == 16 else { throw Failure.invalidHeader }
        let identifier = letters(identifierBytes)
        if let expectedID, !validID(expectedID) || expectedID != identifier { throw Failure.signatureMismatch }
        var hash = SHA256()
        hash.update(data: Data("CRX3 SignedData\0".utf8))
        var length = UInt32(signed.count).littleEndian
        withUnsafeBytes(of: &length) { hash.update(data: Data($0)) }
        hash.update(data: signed)
        let archive = bytes.data((12 + headerLength)..<input.count)
        hash.update(data: archive)
        let digest = hash.finalize()
        for proof in fields where proof.number == 2 || proof.number == 3 {
            let parts = try protobuf(proof.value)
            let key = try single(1, in: parts)
            let signature = try single(2, in: parts)
            guard key.count <= 16384, !signature.isEmpty, signature.count <= 16384,
                  id(forPublicKey: key) == identifier else { continue }
            if proof.number == 3,
               let publicKey = try? P256.Signing.PublicKey(derRepresentation: key),
               let signed = try? P256.Signing.ECDSASignature(derRepresentation: signature),
               publicKey.isValidSignature(signed, for: digest) {
                return Verified(extensionID: identifier, zip: archive, algorithm: "ECDSA P-256 / SHA-256")
            }
            if proof.number == 2, verifyRSA(key: key, signature: signature, digest: Data(digest)) {
                return Verified(extensionID: identifier, zip: archive, algorithm: "RSA PKCS1 / SHA-256")
            }
        }
        throw Failure.signatureMismatch
    }
    private struct Field { let number: UInt64; let value: Data }
    private static func single(_ number: UInt64, in fields: [Field]) throws -> Data {
        let values = fields.filter { $0.number == number }
        guard values.count == 1 else { throw Failure.invalidHeader }
        return values[0].value
    }
    private static func protobuf(_ data: Data) throws -> [Field] {
        let bytes = BinaryBytes(data)
        var offset = 0
        var fields: [Field] = []
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for index in 0..<10 {
                guard offset < data.count else { throw Failure.invalidHeader }
                let byte = bytes.byte(offset); offset += 1
                guard index < 9 || byte <= 1 else { throw Failure.invalidHeader }
                result |= UInt64(byte & 127) << (index * 7)
                if byte & 128 == 0 { return result }
            }
            throw Failure.invalidHeader
        }
        while offset < data.count {
            guard fields.count < 128 else { throw Failure.invalidHeader }
            let tag = try varint()
            guard tag >> 3 > 0, tag >> 3 <= 536_870_911 else { throw Failure.invalidHeader }
            switch tag & 7 {
            case 0: _ = try varint()
            case 1: guard data.count - offset >= 8 else { throw Failure.invalidHeader }; offset += 8
            case 5: guard data.count - offset >= 4 else { throw Failure.invalidHeader }; offset += 4
            case 2:
                let length = try varint()
                guard length <= UInt64(data.count - offset) else { throw Failure.invalidHeader }
                fields.append(Field(number: tag >> 3, value: bytes.data(offset..<(offset + Int(length)))))
                offset += Int(length)
            default: throw Failure.invalidHeader
            }
        }
        return fields
    }
    private static func verifyRSA(key: Data, signature: Data, digest: Data) -> Bool {
        var format = SecExternalFormat.formatOpenSSL
        var type = SecExternalItemType.itemTypePublicKey
        var items: CFArray?
        guard SecItemImport(key as CFData, nil, &format, &type, [], nil, nil, &items) == errSecSuccess,
              let item = (items as? [Any])?.first,
              CFGetTypeID(item as CFTypeRef) == SecKeyGetTypeID() else { return false }
        let publicKey = item as! SecKey
        guard SecKeyIsAlgorithmSupported(publicKey, .verify, .rsaSignatureDigestPKCS1v15SHA256) else { return false }
        return SecKeyVerifySignature(publicKey, .rsaSignatureDigestPKCS1v15SHA256, digest as CFData, signature as CFData, nil)
    }
}

/// Internal, byte-offset access also works for a Data slice with a nonzero index.
struct BinaryBytes {
    let value: Data
    init(_ value: Data) { self.value = value }
    func byte(_ offset: Int) -> UInt8 { value[value.startIndex + offset] }
    func u16(_ offset: Int) -> UInt16 { value.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian } }
    func u32(_ offset: Int) -> UInt32 { value.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian } }
    func data(_ range: Range<Int>) -> Data { Data(value[(value.startIndex + range.lowerBound)..<(value.startIndex + range.upperBound)]) }
}

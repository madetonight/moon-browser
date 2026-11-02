import CryptoKit
import Foundation
import Security
import Testing
import zlib
@testable import MoonCore

@Test func chromeStoreLinksRejectLookalikesAndCredentials() {
    let id = String(repeating: "a", count: 32)
    #expect(ChromePackage.extensionID(in: id) == id)
    #expect(ChromePackage.extensionID(in: "https://chromewebstore.google.com/detail/example/\(id)") == id)
    #expect(ChromePackage.extensionID(in: "https://chrome.google.com/webstore/detail/example/\(id)") == id)
    for text in ["https://chromewebstore.google.com.evil.test/detail/\(id)", "http://chromewebstore.google.com/detail/\(id)", "https://user@chromewebstore.google.com/detail/\(id)", "https://chromewebstore.google.com:444/detail/\(id)", String(repeating: "q", count: 32)] {
        #expect(ChromePackage.extensionID(in: text) == nil)
    }
}

@Test func signedCRXRejectsTamperingAndIdentityMismatch() throws {
    for rsa in [false, true] {
        let fixture = try crx(rsa: rsa)
        let verified = try ChromePackage.verify(fixture.package, expectedID: fixture.id)
        #expect(verified.extensionID == fixture.id)
        #expect(verified.zip == Data("controlled archive payload".utf8))
        var tampered = fixture.package
        tampered[tampered.count - 1] ^= 1
        #expect(throws: ChromePackage.Failure.signatureMismatch) { try ChromePackage.verify(tampered) }
        let mismatch = fixture.id.first == "a" ? String(repeating: "b", count: 32) : String(repeating: "a", count: 32)
        #expect(throws: ChromePackage.Failure.signatureMismatch) { try ChromePackage.verify(fixture.package, expectedID: mismatch) }
        let slice = (Data([1, 2]) + fixture.package).dropFirst(2)
        #expect(try ChromePackage.verify(slice).extensionID == fixture.id)
    }
}

@Test func crxRejectsMalformedFramingAndDuplicateIdentity() throws {
    let fixture = try crx(rsa: false)
    for length in [0, 4, 11, 12, 20] {
        #expect(throws: (any Error).self) { try ChromePackage.verify(Data(fixture.package.prefix(length))) }
    }
    var oversized = Data("Cr24".utf8); oversized.appendLE(UInt32(3)); oversized.appendLE(UInt32.max); oversized.append(0)
    #expect(throws: ChromePackage.Failure.invalidHeader) { try ChromePackage.verify(oversized) }
    let signed = proto(1, Data(repeating: 0, count: 16))
    let header = proto(10000, signed) + proto(10000, signed)
    var duplicate = Data("Cr24".utf8); duplicate.appendLE(UInt32(3)); duplicate.appendLE(UInt32(header.count)); duplicate.append(header); duplicate.append(0)
    #expect(throws: ChromePackage.Failure.invalidHeader) { try ChromePackage.verify(duplicate) }
}

@Test func archivesExtractStoredAndDeflatedFilesAndRefuseExistingDestination() throws {
    // Raw DEFLATE encoding of 1000 lowercase 'a' characters.
    let deflated = Data([0x4b, 0x4c, 0x1c, 0x05, 0xa3, 0x60, 0x14, 0x0c, 0x77, 0x00, 0x00])
    let archive = zip([ZipFile("manifest.json", Data("{}".utf8)), ZipFile("scripts/content.js", Data(repeating: 97, count: 1000), compressed: deflated)])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try ExtensionArchive.extract(archive, to: root)
    #expect(try Data(contentsOf: root.appendingPathComponent("scripts/content.js")) == Data(repeating: 97, count: 1000))
    #expect(throws: ExtensionArchive.Failure.destinationExists) { try ExtensionArchive.extract(archive, to: root) }
    #expect(try Data(contentsOf: root.appendingPathComponent("manifest.json")) == Data("{}".utf8))
}

@Test func archivesRejectTraversalSymlinksAndCaseCollisions() {
    for path in ["../escape", "/escape", "a/../../escape", "a\\escape", "a:escape", "a//escape", "a/./escape"] {
        let archive = zip([ZipFile("manifest.json", Data("{}".utf8)), ZipFile(path, Data())])
        #expect(throws: ExtensionArchive.Failure.unsafePath) { try ExtensionArchive.inspect(archive) }
    }
    #expect(throws: ExtensionArchive.Failure.unsafePath) { try ExtensionArchive.inspect(zip([ZipFile("manifest.json", Data()), ZipFile("MANIFEST.JSON", Data())])) }
    #expect(throws: ExtensionArchive.Failure.unsupported) { try ExtensionArchive.inspect(zip([ZipFile("manifest.json", Data()), ZipFile("link", Data("/tmp".utf8), mode: 0xa000)])) }
}

@Test func corruptedArchivesRollBackAndBoundActualInflatedOutput() throws {
    let deflated = Data([0x4b, 0x4c, 0x1c, 0x05, 0xa3, 0x60, 0x14, 0x0c, 0x77, 0x00, 0x00])
    let archives = [
        zip([ZipFile("manifest.json", Data("{}".utf8), crc: 123)]),
        zip([ZipFile("manifest.json", Data("{}".utf8)), ZipFile("bomb", Data(repeating: 97, count: 1000), compressed: deflated, declaredSize: 10)])
    ]
    for archive in archives {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: ExtensionArchive.Failure.corrupted) { try ExtensionArchive.extract(archive, to: root) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

private func crx(rsa: Bool) throws -> (package: Data, id: String) {
    let archive = Data("controlled archive payload".utf8)
    let key: Data
    let signer: (Data) throws -> Data
    if rsa {
        let privateKey = try #require(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let raw = try #require(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
        let algorithm = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        key = der(0x30, algorithm + der(0x03, Data([0]) + raw))
        signer = { message in try #require(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, nil)) as Data }
    } else {
        let privateKey = P256.Signing.PrivateKey()
        key = privateKey.publicKey.derRepresentation
        signer = { try privateKey.signature(for: $0).derRepresentation }
    }
    let id = ChromePackage.id(forPublicKey: key)
    let signed = proto(1, Data(SHA256.hash(data: key).prefix(16)))
    var message = Data("CRX3 SignedData\0".utf8); message.appendLE(UInt32(signed.count)); message.append(signed); message.append(archive)
    let header = proto(rsa ? 2 : 3, proto(1, key) + proto(2, try signer(message))) + proto(10000, signed)
    var package = Data("Cr24".utf8); package.appendLE(UInt32(3)); package.appendLE(UInt32(header.count)); package.append(header); package.append(archive)
    return (package, id)
}
private func der(_ tag: UInt8, _ value: Data) -> Data {
    let length = value.count < 128 ? Data([UInt8(value.count)]) : Data([0x82, UInt8(value.count >> 8), UInt8(value.count & 255)])
    return Data([tag]) + length + value
}
private func varint(_ value: UInt64) -> Data {
    var value = value, data = Data()
    repeat { let byte = UInt8(value & 127); value >>= 7; data.append(byte | (value > 0 ? 128 : 0)) } while value > 0
    return data
}
private func proto(_ number: UInt64, _ value: Data) -> Data { varint((number << 3) | 2) + varint(UInt64(value.count)) + value }
private extension Data { mutating func appendLE<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) } } }
private struct ZipFile {
    var name: String, data: Data, compressed: Data?, declaredSize: Int?, crc: UInt32?, mode: UInt32
    init(_ name: String, _ data: Data, compressed: Data? = nil, declaredSize: Int? = nil, crc: UInt32? = nil, mode: UInt32 = 0x8000) { self.name = name; self.data = data; self.compressed = compressed; self.declaredSize = declaredSize; self.crc = crc; self.mode = mode }
}
private func zip(_ files: [ZipFile]) -> Data {
    var archive = Data(), directory = Data()
    for file in files {
        let offset = archive.count, name = Data(file.name.utf8), payload = file.compressed ?? file.data
        let crc = file.crc ?? UInt32(truncatingIfNeeded: file.data.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) })
        let size = UInt32(file.declaredSize ?? file.data.count), method: UInt16 = file.compressed == nil ? 0 : 8
        archive.appendLE(UInt32(0x04034b50)); archive.appendLE(UInt16(20)); archive.appendLE(UInt16(0)); archive.appendLE(method); archive.appendLE(UInt32(0)); archive.appendLE(crc); archive.appendLE(UInt32(payload.count)); archive.appendLE(size); archive.appendLE(UInt16(name.count)); archive.appendLE(UInt16(0)); archive.append(name); archive.append(payload)
        directory.appendLE(UInt32(0x02014b50)); directory.appendLE(UInt16(0x0314)); directory.appendLE(UInt16(20)); directory.appendLE(UInt16(0)); directory.appendLE(method); directory.appendLE(UInt32(0)); directory.appendLE(crc); directory.appendLE(UInt32(payload.count)); directory.appendLE(size); directory.appendLE(UInt16(name.count)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(UInt16(0)); directory.appendLE(file.mode << 16); directory.appendLE(UInt32(offset)); directory.append(name)
    }
    let start = archive.count; archive.append(directory)
    archive.appendLE(UInt32(0x06054b50)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(files.count)); archive.appendLE(UInt16(files.count)); archive.appendLE(UInt32(directory.count)); archive.appendLE(UInt32(start)); archive.appendLE(UInt16(0))
    return archive
}

@Test func resourceRedirectPoliciesRejectHostLookalikesAndDowngrades() {
    let chrome = ResourcePolicy.chromePackage
    #expect(chrome.allows(URL(string: "https://clients2.google.com/service/update2/crx")!))
    #expect(chrome.allows(URL(string: "https://clients2.googleusercontent.com/crx")!))
    for target in ["https://googleusercontent.com.evil.test/crx", "http://clients2.google.com/crx", "https://user@clients2.google.com/crx", "https://127.0.0.1/crx"] {
        #expect(!chrome.allows(URL(string: target)!))
    }
    let same = ResourcePolicy.sameOrigin(URL(string: "https://example.com/favicon.ico")!)
    #expect(same.allows(URL(string: "https://example.com/icon.png")!))
    #expect(!same.allows(URL(string: "http://example.com/icon.png")!))
    #expect(!same.allows(URL(string: "https://example.com:444/icon.png")!))
    #expect(!same.allows(URL(string: "https://other.example.com/icon.png")!))
}

@Test func unpackedExtensionsCopyWithoutFollowingSymlinks() throws {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
    try Data("{}".utf8).write(to: source.appendingPathComponent("manifest.json"))
    try ExtensionArchive.stageDirectory(source, to: target)
    #expect(try Data(contentsOf: target.appendingPathComponent("manifest.json")) == Data("{}".utf8))
    try FileManager.default.removeItem(at: target)
    try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/private/tmp"))
    #expect(throws: ExtensionArchive.Failure.unsupported) { try ExtensionArchive.stageDirectory(source, to: target) }
    #expect(!FileManager.default.fileExists(atPath: target.path))
}

@Test func selectedPackagesAreBoundedSnapshotsAndRejectLinks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("fixture.crx"), link = directory.appendingPathComponent("link.crx")
    let bytes = Data("Controlled package".utf8)
    try bytes.write(to: source)
    let snapshot = try ExtensionArchive.readPackage(source)
    try Data("Changed later".utf8).write(to: source)
    #expect(snapshot == bytes)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    #expect(throws: ExtensionArchive.Failure.unsafePath) { try ExtensionArchive.readPackage(link) }
    #expect(throws: ExtensionArchive.Failure.unsupported) { try ExtensionArchive.readPackage(directory) }
    let handle = try FileHandle(forWritingTo: source)
    try handle.truncate(atOffset: UInt64(ChromePackage.maximumBytes + 1)); try handle.close()
    #expect(throws: ExtensionArchive.Failure.tooLarge) { try ExtensionArchive.readPackage(source) }
}

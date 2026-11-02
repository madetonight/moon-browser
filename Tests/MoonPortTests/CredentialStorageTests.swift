import Foundation
import AppKit
import MoonCore
import XCTest
import WebKit
@testable import Moon

@MainActor final class CredentialStorageTests: XCTestCase {
    private let raw = "https://fixture-user:fixture-password@example.test:8443/path?q=keep#section"
    private let clean = "https://example.test:8443/path?q=keep#section"
    private var originals: [URL: Data?] = [:]
    private func preserve(_ file: URL) { originals[file] = .some(try? Data(contentsOf: file)) }
    override func tearDown() {
        Disk.drain()
        for (file, bytes) in originals {
            if let bytes { try? bytes.write(to: file) } else { try? FileManager.default.removeItem(at: file) }
        }
        originals = [:]
        super.tearDown()
    }
    func testSessionWritesNoURLCredentialsAndPreservesDestination() throws {
        let file = Store.file("session.json"); preserve(file)
        Session.write(now: true, .init(tabs: [.init(url: raw, title: "Fixture", pin: "F", home: raw)], active: 0))
        let bytes = try Data(contentsOf: file)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("fixture-password"))
        let restored = Session.read()
        XCTAssertEqual(restored.tabs.first?.url, clean)
        XCTAssertEqual(restored.tabs.first?.home, clean)
    }
    func testLegacySessionsAreCleanedBeforeUseAndRewritten() throws {
        let file = Store.file("session.json"); preserve(file)
        let old = Session.Shape(tabs: [.init(url: raw, title: "Fixture", pin: "F", home: raw)], active: 0)
        try FileManager.default.createDirectory(at: Store.folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(old).write(to: file)
        XCTAssertEqual(Session.read().tabs.first?.url, clean)
        Disk.drain()
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("fixture-password"))
    }
    func testBookmarkAddEditAndExportDoNotExposeURLCredentials() throws {
        let name = "credential-bookmarks-\(UUID().uuidString).json"
        let file = Store.file(name); preserve(file)
        let marks = Bookmarks(file: name)
        let node = try XCTUnwrap(marks.add(URL(string: raw)!, title: "Fixture"))
        XCTAssertEqual(node.url, clean)
        XCTAssertTrue(marks.contains(URL(string: raw)!))
        XCTAssertEqual(marks.bookmark(for: URL(string: raw)!)?.id, node.id)
        marks.update(node.id, title: nil, url: raw)
        XCTAssertEqual(marks.roots.first?.url, clean)
        Disk.drain()
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("fixture-password"))
        let exported = BookmarkDocument.export([PageRecord(title: "Fixture", url: URL(string: raw)!)])
        XCTAssertFalse(exported.contains("fixture-password"))
        XCTAssertTrue(exported.contains("q=keep"))
    }
    func testPinAndSecondaryWindowSerializersStripCredentials() throws {
        let pin = PinDef(id: UUID(), letter: "F", home: raw, title: "Fixture")
        let bytes = try XCTUnwrap(Pins.encode(bySpace: [:], shared: [pin]))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("fixture-password"))
        XCTAssertEqual(Pins.decode(bytes)?.shared.first?.home, clean)
        let file = Store.file("windows.json"); preserve(file)
        var record = Moon.WindowRecord()
        record.rows = [Space.firstID.uuidString: .init(tabs: [.init(url: raw, title: "Fixture", pin: nil)], active: 0)]
        let snapshot = [record]
        Disk.write(file, now: true) { try? JSONEncoder().encode(snapshot) }
        let value = try JSONDecoder().decode([Moon.WindowRecord].self, from: Data(contentsOf: file))
        XCTAssertEqual(value.first?.rows.values.first?.tabs.first?.url, clean)
    }
    func testBrowserMetadataFilesAreOwnerOnly() throws {
        let file = Store.file("credential-permissions.json"); preserve(file)
        Disk.write(file, now: true) { Data("{}".utf8) }
        let files = FileManager.default
        let mode = try XCTUnwrap(try files.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)
        let directoryMode = try XCTUnwrap(try files.attributesOfItem(atPath: Store.folder.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(mode.intValue & 0o077, 0)
        XCTAssertEqual(directoryMode.intValue & 0o077, 0)
    }
    func testOversizedImportReadIsRejectedBeforeAccumulation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Moon-import-limit-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(ExtensionArchive.maximumFileBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try ImportFile.readData(file, control: .init()) { _, _ in })
    }
    func testEncodedURLCredentialsAreRemovedFromOlderJSON() throws {
        let file = Store.file("session.json"); preserve(file)
        let encoded = "https://fixture%2Duser:fixture%2Dpassword@example.test/path?q=keep"
        let old = Session.Shape(tabs: [.init(url: encoded, title: "Fixture", pin: nil)], active: 0)
        let text = String(decoding: try JSONEncoder().encode(old), as: UTF8.self).replacingOccurrences(of: "@", with: "\\u0040")
        try FileManager.default.createDirectory(at: Store.folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        let url = try XCTUnwrap(Session.read().tabs.first.flatMap { URL(string: $0.url) })
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
        XCTAssertEqual(url.query, "q=keep")
    }
    func testUncredentialedDestinationsRemainUnchanged() throws {
        let ordinary = "https://example.test:8443/a%20b?q=value#section"
        XCTAssertEqual(MoonCore.MetadataPrivacy.address(ordinary), ordinary)
        XCTAssertEqual(MoonCore.MetadataPrivacy.address("moon://settings/passwords"), "moon://settings/passwords")
    }
    func testImportArchiveRejectsTraversalAndOversizedIgnoredMembers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Moon-zip-limits-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1], 'w', zipfile.ZIP_DEFLATED); z.writestr(sys.argv[2], b'0'*int(sys.argv[3])); z.close()"
        for (name, size) in [("../escaped.csv", 32), ("ignored.dat", ExtensionArchive.maximumFileBytes + 1)] {
            let file = root.appendingPathComponent(UUID().uuidString + ".zip")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", script, file.path, name, String(size)]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertThrowsError(try ImportFile.read(file))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.csv").path))
        }
    }

    func testExtensionTabMetadataRedactsCredentialsWithoutChangingNavigation() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Moon-extension-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest: [String: Any] = ["manifest_version": 3, "name": "Metadata fixture", "version": "1", "permissions": ["tabs"]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: folder))
        let tab = Moon.Tab()
        tab.restore(url: URL(string: raw)!, title: "Fixture")
        let exposed = ExtensionTab(tab: tab, owner: .shared).url(for: context)
        XCTAssertEqual(exposed?.absoluteString, clean)
        XCTAssertEqual(tab.address?.absoluteString, raw, "Authentication input remains transient for the actual request")
    }
    func testNonUTF8UserinfoIsAlsoRedacted() {
        let value = "https://%FF:%FE@example.test/path?q=keep"
        XCTAssertEqual(MoonCore.MetadataPrivacy.address(value), "https://example.test/path?q=keep")
    }

    func testSchemeRelativeBookmarkCredentialsAreRedacted() throws {
        let name = "bookmarks-relative-\(UUID().uuidString).json"
        let file = Store.file(name); preserve(file)
        let marks = Bookmarks(file: name)
        let source = try XCTUnwrap(URL(string: "//fixture-user:fixture-password@example.test/path?q=keep"))
        let node = try XCTUnwrap(marks.add(source, title: "Fixture"))
        XCTAssertEqual(node.url, "//example.test/path?q=keep")
        marks.update(node.id, title: nil, url: source.absoluteString)
        XCTAssertEqual(marks.bookmark(for: source)?.id, node.id)
        Disk.drain()
        XCTAssertFalse(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("fixture-password"))
    }

    func testRememberedSidePanelCleansNewAndLegacyCredentials() {
        let store = Store.settings
        let original = store.object(forKey: "panel.site")
        defer {
            if let original { store.set(original, forKey: "panel.site") }
            else { store.removeObject(forKey: "panel.site") }
        }
        store.set(raw, forKey: "panel.site")
        let prefs = Preferences()
        XCTAssertEqual(prefs.panelSite, clean)
        XCTAssertEqual(store.string(forKey: "panel.site"), clean)
        prefs.panelSite = raw
        XCTAssertEqual(prefs.panelSite, clean)
        XCTAssertEqual(store.string(forKey: "panel.site"), clean)
    }

}

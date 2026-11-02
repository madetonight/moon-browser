import Foundation
import MoonCore

/// Import the earlier Moon library once. Keep the source, with URL authentication
/// userinfo removed before reuse.
/// All new files are prepared before publication. Existing port files win.
enum MoonMigration {
    struct Prepared {
        var files: [String: Data]
        var selectedSpace: UUID?
    }

    static func prepare(_ data: Data) throws -> Prepared {
        let old = try JSONDecoder().decode(LibraryRecord.self, from: MetadataPrivacy.json(data))
        let encoder = JSONEncoder()
        let first = old.spaces.first
        func spaceID(_ id: UUID) -> UUID {
            id == first?.id && first?.isolated == false ? Space.firstID : id
        }
        var spaces = old.spaces.map {
            Space(id: spaceID($0.id), name: $0.name, colour: 0, sharesSignIns: !$0.isolated)
        }
        if !spaces.contains(where: { $0.id == Space.firstID }) {
            spaces.insert(Space(id: Space.firstID, name: "Personal", colour: 0, sharesSignIns: true), at: 0)
        }
        var files: [String: Data] = [:]
        let hidden = old.hiddenSelectors.mapValues { $0.map { Veil(selector: $0, label: $0, date: Date()) } }
        files["hidden.json"] = try encoder.encode(hidden)
        files["spaces.json"] = try encoder.encode(spaces)
        let bookmarks = old.bookmarks.map { Bookmark.site($0.title, $0.url) }
        files["bookmarks.json"] = try encoder.encode(bookmarks)
        // History's persisted schema deliberately contains no WebKit state.
        struct Visit: Encodable { var url: String; var key: String; var title: String; var count: Int; var last: Date }
        files["history.json"] = try encoder.encode(old.history.map {
            Visit(url: $0.url.absoluteString, key: Address.pretty($0.url), title: $0.title, count: 1, last: $0.date)
        })
        var windows: [WindowRecord] = []
        for (index, window) in old.windows.enumerated() {
            var saved = WindowRecord(space: spaceID(window.spaceID))
            for space in old.spaces {
                let tabs = window.tabs.filter { $0.spaceID == space.id }
                let entries = tabs.map { tab -> Session.Entry in
                    let url = tab.internalPage == "settings" ? "moon://settings" : tab.url?.absoluteString ?? "about:blank"
                    return Session.Entry(url: url, title: tab.title, pin: tab.pinned ? String(tab.title.prefix(1)).uppercased() : nil, pinID: tab.pinned ? tab.id : nil)
                }
                let shape = Session.Shape(tabs: entries, active: tabs.firstIndex(where: { $0.id == window.selectedID }) ?? 0)
                let id = spaceID(space.id)
                if index == 0 {
                    files[id == Space.firstID ? "session.json" : "session-\(id.uuidString).json"] = try encoder.encode(shape)
                } else { saved.rows[id.uuidString] = shape }
            }
            windows.append(saved)
        }
        if !windows.isEmpty { files["windows.json"] = try encoder.encode(windows) }
        return Prepared(files: files, selectedSpace: old.windows.first.map { spaceID($0.spaceID) })
    }

    static func run() {
        let folder = Store.folder
        let legacy = folder.appendingPathComponent("Library.json")
        let marker = folder.appendingPathComponent("moon-search107-migrated")
        let fm = FileManager.default
        guard let data = Disk.read(legacy), !fm.fileExists(atPath: marker.path) else { return }
        do {
            let prepared = try prepare(data)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for (name, bytes) in prepared.files {
                let target = folder.appendingPathComponent(name)
                guard !fm.fileExists(atPath: target.path) else { continue }
                try bytes.write(to: target, options: .withoutOverwriting)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            }
            let settings = Store.settings
            func carry(_ old: String, _ new: String, transform: (Any) -> Any = { $0 }) {
                if settings.object(forKey: new) == nil, let value = settings.object(forKey: old) { settings.set(transform(value), forKey: new) }
            }
            carry("horizontalTabs", "sidebar") { !(($0 as? Bool) ?? false) }
            carry("appearance", "look")
            carry("engine", "search.engine") { ($0 as? String)?.lowercased() ?? "duckduckgo" }
            carry("blocker", "shield")
            settings.set(true, forKey: "welcomed")
            settings.set("ollama", forKey: "ai.provider")
            let legacy = try JSONDecoder().decode(LibraryRecord.self, from: MetadataPrivacy.json(data))
            if settings.object(forKey: "shield.paused") == nil { settings.set(Array(legacy.unblockedHosts), forKey: "shield.paused") }
            if settings.object(forKey: "tabs.awakeSites") == nil { settings.set(Array(legacy.awakeHosts), forKey: "tabs.awakeSites") }
            if let options = settings.dictionary(forKey: "settings.options") {
                for (key, value) in options where settings.object(forKey: key) == nil { settings.set(value, forKey: key) }
                if let enabled = options["ai.enabled"] as? Bool { settings.set(enabled, forKey: "ai") }
            }
            if let choices = settings.dictionary(forKey: "settings.choices") {
                if let model = choices["ai.model"] as? String { settings.set(["ollama": model], forKey: "ai.models") }
                if let side = choices["tabs.side"] as? String { settings.set(side, forKey: "sidebar.position") }
                if let width = choices["sidebar.width"] as? String, let value = Double(width) { settings.set(value, forKey: "sidebar.width") }
            }
            if let space = prepared.selectedSpace { settings.set(space.uuidString, forKey: "space.current") }
            try Data("Moon imported Library.json; the original remains intact.\n".utf8).write(to: marker, options: .atomic)
        } catch {
            // A malformed legacy library is retained for recovery, never reset.
            NSLog("Moon could not migrate its previous library. The original is preserved.")
        }
    }
}

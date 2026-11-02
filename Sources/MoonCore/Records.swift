import Foundation

public struct PageRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var date: Date
    public init(id: UUID = UUID(), title: String, url: URL, date: Date = Date()) {
        self.id = id; self.title = title; self.url = url; self.date = date
    }
}

public struct TabRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL?
    public var pinned: Bool
    public var spaceID: UUID
    public var internalPage: String?
    public init(id: UUID = UUID(), title: String = "New Tab", url: URL? = nil, pinned: Bool = false, spaceID: UUID) {
        self.id = id; self.title = title; self.url = url; self.pinned = pinned; self.spaceID = spaceID
    }
}

public struct SpaceRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isolated: Bool
    public init(id: UUID = UUID(), name: String, isolated: Bool = false) {
        self.id = id; self.name = name; self.isolated = isolated
    }
}

public struct WindowRecord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var tabs: [TabRecord]
    public var selectedID: UUID?
    public var spaceID: UUID
    public init(id: UUID, tabs: [TabRecord], selectedID: UUID?, spaceID: UUID) {
        self.id = id; self.tabs = tabs; self.selectedID = selectedID; self.spaceID = spaceID
    }
}

public struct LibraryRecord: Codable, Sendable {
    public var bookmarks: [PageRecord] = []
    public var history: [PageRecord] = []
    public var spaces: [SpaceRecord] = [SpaceRecord(name: "Personal")]
    public var windows: [WindowRecord] = []
    public var hiddenSelectors: [String: [String]] = [:]
    public var unblockedHosts: Set<String> = []
    public var awakeHosts: Set<String> = []
    public init() {}
}

public enum BookmarkDocument {
    public static func export(_ bookmarks: [PageRecord]) -> String {
        let rows = bookmarks.map { "<DT><A HREF=\"\(escape(MetadataPrivacy.address($0.url.absoluteString)))\">\(escape($0.title))</A>" }.joined(separator: "\n")
        return "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n<TITLE>Moon Bookmarks</TITLE>\n<H1>Moon Bookmarks</H1>\n<DL><p>\n\(rows)\n</DL><p>\n"
    }
    public static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

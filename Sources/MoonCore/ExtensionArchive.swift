import Darwin
import Foundation
import zlib

/// Bounded ZIP extraction. No shell, symlinks, archive paths, or advertised sizes
/// are trusted. Actual inflated output and CRC are checked before installation.
public enum ExtensionArchive {
    public static let maximumExpandedBytes = 128 * 1024 * 1024
    public static let maximumFileBytes = 32 * 1024 * 1024
    public struct Entry: Sendable {
        public let path: String
        public let size: Int
        public let directory: Bool
        let method: UInt16
        let crc: UInt32
        let payload: Range<Int>
    }
    public enum Failure: String, Error, LocalizedError, Sendable {
        case malformed, unsafePath, unsupported, tooLarge, corrupted, destinationExists
        public var errorDescription: String? {
            switch self {
            case .malformed: "This extension archive is malformed."
            case .unsafePath: "The extension contains an unsafe or conflicting file path."
            case .unsupported: "This archive uses unsupported ZIP features or contains symbolic links."
            case .tooLarge: "The extension exceeds Moon's safe extraction limits."
            case .corrupted: "An extension file is corrupted or expands beyond its declared size."
            case .destinationExists: "The extension staging folder already exists."
            }
        }
    }
    /// Read a stable, bounded snapshot rather than mapping a mutable selected file.
    public static func readPackage(_ source: URL) throws -> Data {
        let input = source.withUnsafeFileSystemRepresentation { $0.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) } ?? -1 }
        guard input >= 0 else { throw Failure.unsafePath }
        defer { close(input) }
        var metadata = stat()
        guard fstat(input, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else { throw Failure.unsupported }
        guard metadata.st_size >= 0, metadata.st_size <= ChromePackage.maximumBytes else { throw Failure.tooLarge }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, $0.count) }
            if count < 0 { if errno == EINTR { continue }; throw Failure.malformed }
            if count == 0 { return data }
            guard count <= ChromePackage.maximumBytes - data.count else { throw Failure.tooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
    public static func inspect(_ input: Data, requireManifest: Bool = true) throws -> [Entry] {
        guard input.count >= 22, input.count <= ChromePackage.maximumBytes else { throw Failure.tooLarge }
        let bytes = BinaryBytes(input)
        var end: Int?
        let lower = max(0, input.count - 65557)
        for index in stride(from: input.count - 22, through: lower, by: -1) {
            if bytes.u32(index) == 0x06054b50, index + 22 + Int(bytes.u16(index + 20)) == input.count { end = index; break }
        }
        guard let end, bytes.u16(end + 4) == 0, bytes.u16(end + 6) == 0,
              bytes.u16(end + 8) == bytes.u16(end + 10) else { throw Failure.malformed }
        let count = Int(bytes.u16(end + 10))
        let centralSize = Int(bytes.u32(end + 12))
        let central = Int(bytes.u32(end + 16))
        guard count > 0, count <= 10000, central <= end, centralSize == end - central else { throw Failure.malformed }
        var cursor = central
        var total = 0
        var entries: [Entry] = []
        var seen = Set<String>()
        var intervals: [Range<Int>] = []
        for _ in 0..<count {
            guard end - cursor >= 46, bytes.u32(cursor) == 0x02014b50 else { throw Failure.malformed }
            let flags = bytes.u16(cursor + 8)
            let method = bytes.u16(cursor + 10)
            let compressed = Int(bytes.u32(cursor + 20))
            let expanded = Int(bytes.u32(cursor + 24))
            let nameLength = Int(bytes.u16(cursor + 28))
            let extraLength = Int(bytes.u16(cursor + 30))
            let commentLength = Int(bytes.u16(cursor + 32))
            let offset = Int(bytes.u32(cursor + 42))
            let mode = (bytes.u32(cursor + 38) >> 16) & 0xf000
            guard flags & 1 == 0, method == 0 || method == 8,
                  bytes.u16(cursor + 34) == 0,
                  mode == 0 || mode == 0x8000 || mode == 0x4000 else { throw Failure.unsupported }
            guard expanded <= maximumFileBytes, compressed <= ChromePackage.maximumBytes,
                  nameLength > 0, nameLength <= 4096,
                  nameLength + extraLength + commentLength <= end - cursor - 46 else { throw Failure.tooLarge }
            let nameBytes = bytes.data((cursor + 46)..<(cursor + 46 + nameLength))
            guard let path = String(data: nameBytes, encoding: .utf8) else { throw Failure.unsafePath }
            let directory = path.hasSuffix("/")
            let normalized = try safePath(path)
            guard seen.insert(normalized).inserted,
                  mode != 0x4000 || directory,
                  !directory || expanded == 0 else { throw Failure.unsafePath }
            guard offset <= central, central - offset >= 30,
                  bytes.u32(offset) == 0x04034b50,
                  bytes.u16(offset + 6) == flags, bytes.u16(offset + 8) == method else { throw Failure.malformed }
            let localName = Int(bytes.u16(offset + 26))
            let localExtra = Int(bytes.u16(offset + 28))
            guard localName == nameLength, localName + localExtra <= central - offset - 30,
                  bytes.data((offset + 30)..<(offset + 30 + localName)) == nameBytes else { throw Failure.malformed }
            let start = offset + 30 + localName + localExtra
            guard compressed <= central - start, method != 0 || compressed == expanded else { throw Failure.malformed }
            guard path != "manifest.json" || expanded <= 1_048_576 else { throw Failure.tooLarge }
            total += expanded
            guard total <= maximumExpandedBytes else { throw Failure.tooLarge }
            intervals.append(offset..<(start + compressed))
            entries.append(Entry(path: path, size: expanded, directory: directory, method: method, crc: bytes.u32(cursor + 16), payload: start..<(start + compressed)))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard cursor == end, !requireManifest || entries.contains(where: { $0.path == "manifest.json" && !$0.directory }) else { throw Failure.malformed }
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        for index in 1..<sorted.count where sorted[index].lowerBound < sorted[index - 1].upperBound { throw Failure.malformed }
        return entries
    }
    private static func safePath(_ path: String) throws -> String {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw Failure.unsafePath }
        let value = path.hasSuffix("/") ? String(path.dropLast()) : path
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 32, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw Failure.unsafePath }
        return value.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
    public static func extract(_ input: Data, to root: URL, requireManifest: Bool = true,
                               include: (Entry) -> Bool = { _ in true },
                               check: (() throws -> Void)? = nil) throws {
        let entries = try inspect(input, requireManifest: requireManifest)
        let files = FileManager.default
        guard !files.fileExists(atPath: root.path), (try? files.destinationOfSymbolicLink(atPath: root.path)) == nil else { throw Failure.destinationExists }
        try files.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var success = false
        defer { if !success { try? files.removeItem(at: root) } }
        let bytes = BinaryBytes(input)
        for entry in entries where include(entry) {
            try check?()
            try Task.checkCancellation()
            let target = root.appendingPathComponent(entry.path)
            if entry.directory {
                try files.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                continue
            }
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let descriptor = target.withUnsafeFileSystemRepresentation { path in path.map { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) } ?? -1 }
            guard descriptor >= 0 else { throw Failure.unsafePath }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                let payload = bytes.data(entry.payload)
                if entry.method == 0 {
                    let checksum = payload.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(payload.count)) }
                    guard UInt32(truncatingIfNeeded: checksum) == entry.crc else { throw Failure.corrupted }
                    try handle.write(contentsOf: payload)
                } else { try inflate(payload, entry: entry, to: handle, check: check) }
                try handle.close()
            } catch { try? handle.close(); throw error }
        }
        success = true
    }
    /// Copy through directory descriptors so a source symlink cannot escape the selected tree.
    public static func stageDirectory(_ source: URL, to root: URL) throws {
        let descriptor = source.withUnsafeFileSystemRepresentation { $0.map { open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) } ?? -1 }
        guard descriptor >= 0 else { throw Failure.unsafePath }
        defer { close(descriptor) }
        guard !FileManager.default.fileExists(atPath: root.path), (try? FileManager.default.destinationOfSymbolicLink(atPath: root.path)) == nil else { throw Failure.destinationExists }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: root) } }
        var count = 0, total = 0
        var seen = Set<String>()
        try copyDirectory(descriptor, to: root, prefix: "", depth: 0, count: &count, total: &total, seen: &seen)
        var manifest = stat()
        guard fstatat(descriptor, "manifest.json", &manifest, AT_SYMLINK_NOFOLLOW) == 0, manifest.st_mode & S_IFMT == S_IFREG else { throw Failure.malformed }
        success = true
    }
    private static func copyDirectory(_ descriptor: Int32, to root: URL, prefix: String, depth: Int, count: inout Int, total: inout Int, seen: inout Set<String>) throws {
        guard depth < 32 else { throw Failure.unsafePath }
        let copy = dup(descriptor)
        guard copy >= 0 else { throw Failure.malformed }
        guard let directory = fdopendir(copy) else { close(copy); throw Failure.malformed }
        defer { closedir(directory) }
        while true {
            errno = 0
            guard let entry = readdir(directory) else { guard errno == 0 else { throw Failure.malformed }; break }
            guard let name = withUnsafePointer(to: &entry.pointee.d_name, { String(validatingCString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)) }) else { throw Failure.unsafePath }
            if name == "." || name == ".." { continue }
            try Task.checkCancellation()
            count += 1; guard count <= 10000 else { throw Failure.tooLarge }
            let path = prefix + name
            guard seen.insert(try safePath(path)).inserted else { throw Failure.unsafePath }
            var metadata = stat()
            guard fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else { throw Failure.malformed }
            let type = metadata.st_mode & S_IFMT
            let target = root.appendingPathComponent(name)
            if type == S_IFDIR {
                let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard child >= 0 else { throw Failure.unsafePath }
                defer { close(child) }
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                try copyDirectory(child, to: target, prefix: path + "/", depth: depth + 1, count: &count, total: &total, seen: &seen)
            } else if type == S_IFREG {
                guard metadata.st_size >= 0, metadata.st_size <= maximumFileBytes, path != "manifest.json" || metadata.st_size <= 1_048_576 else { throw Failure.tooLarge }
                let input = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                guard input >= 0 else { throw Failure.unsafePath }
                defer { close(input) }
                var opened = stat()
                guard fstat(input, &opened) == 0, opened.st_mode & S_IFMT == S_IFREG else { throw Failure.unsafePath }
                let output = target.withUnsafeFileSystemRepresentation { $0.map { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) } ?? -1 }
                guard output >= 0 else { throw Failure.unsafePath }
                let handle = FileHandle(fileDescriptor: output, closeOnDealloc: true)
                do {
                    var buffer = [UInt8](repeating: 0, count: 65536), size = 0
                    while true {
                        try Task.checkCancellation()
                        let received = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, $0.count) }
                        if received < 0 { if errno == EINTR { continue }; throw Failure.malformed }
                        if received == 0 { break }
                        size += received; total += received
                        guard size <= maximumFileBytes, total <= maximumExpandedBytes, path != "manifest.json" || size <= 1_048_576 else { throw Failure.tooLarge }
                        try handle.write(contentsOf: Data(buffer.prefix(received)))
                    }
                    try handle.close()
                } catch { try? handle.close(); throw error }
            } else { throw Failure.unsupported }
        }
    }
    private static func inflate(_ input: Data, entry: Entry, to file: FileHandle, check: (() throws -> Void)? = nil) throws {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.corrupted }
        defer { inflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: 65536)
        var written = 0
        var checksum: uLong = 0
        try input.withUnsafeBytes { source in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            while true {
                try check?()
                try Task.checkCancellation()
                let status = output.withUnsafeMutableBytes { destination in
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(destination.count)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                let count = output.count - Int(stream.avail_out)
                written += count
                guard written <= entry.size else { throw Failure.corrupted }
                if count > 0 {
                    checksum = output.withUnsafeBufferPointer { crc32(checksum, $0.baseAddress, uInt(count)) }
                    try file.write(contentsOf: Data(output.prefix(count)))
                }
                if status == Z_STREAM_END { break }
                guard status == Z_OK, count > 0 || stream.avail_in > 0 else { throw Failure.corrupted }
            }
        }
        guard written == entry.size, stream.avail_in == 0,
              UInt32(truncatingIfNeeded: checksum) == entry.crc else { throw Failure.corrupted }
    }
}

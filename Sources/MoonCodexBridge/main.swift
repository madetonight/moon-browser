import AppKit
import Foundation
import Security
import Darwin
import MoonCore
import OSLog

/// A local, on-demand launcher. Only the official signed Codex executable is
/// accepted. Its account lives separately; Moon's browser data is never a cwd.
@main
struct MoonCodexBridge {
    static let log = Logger(subsystem: "org.moonbrowser.Moon.CodexBridge", category: "startup")
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = BridgeDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    static func runBridge(directory requestedDirectory: URL) {
        log.notice("Companion started; argument count: \(CommandLine.arguments.count)")
        let owner = Bundle.main.object(forInfoDictionaryKey: "MoonOwnerBundleID") as? String ?? "org.moonbrowser.Moon"
        // A launch from the sandboxed browser can carry its container home.
        // The separately launched companion must resolve the account's actual
        // home from the OS rather than append a second container to that path.
        guard let homePath = getpwuid(getuid())?.pointee.pw_dir else { return }
        let home = URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        let permitted = home.appendingPathComponent("Library/Containers/\(owner)/Data/Library/Application Support/Moon/Codex Bridge").standardizedFileURL
        let directory = requestedDirectory.standardizedFileURL
        guard directory.deletingLastPathComponent().path == permitted.path,
              UUID(uuidString: directory.lastPathComponent) != nil,
              secure(directory, mode: 0o700), secure(directory.appendingPathComponent("request.json"), mode: 0o600)
        else {
            log.error("Connection directory rejected; expected parent: \(directory.deletingLastPathComponent().path == permitted.path), secure directory: \(secure(directory, mode: 0o700)), secure request: \(secure(directory.appendingPathComponent("request.json"), mode: 0o600))")
            return
        }
        func publish(_ value: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
            let url = directory.appendingPathComponent("status.json")
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        do {
            let request = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("request.json"))) as? [String: Any]
            guard let token = request?["token"] as? String, token.utf8.count == 64,
                  token.allSatisfy({ $0.isHexDigit }) else { return }
            let candidates = [
                home.appendingPathComponent(".local/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"),
                URL(fileURLWithPath: "/opt/homebrew/bin/codex"), URL(fileURLWithPath: "/usr/local/bin/codex")
            ] + ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/opt/homebrew/Caskroom/codex"), includingPropertiesForKeys: nil).flatMap { folder in
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            }) ?? [])
            guard let engine = candidates.map({ $0.resolvingSymlinksInPath() }).first(where: trusted) else {
                publish(["error": "Install the official Codex CLI, then choose Connect again."]); return
            }
            let support = home.appendingPathComponent("Library/Application Support/Moon Codex", isDirectory: true)
            let workspace = support.appendingPathComponent("Workspace", isDirectory: true)
            let account = support.appendingPathComponent("Account", isDirectory: true)
            for folder in [support, workspace, account] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                guard secure(folder, mode: 0o700) else { throw Failure.unsafePath }
            }
            try Data(CodexPolicy.configuration.utf8).write(to: account.appendingPathComponent("config.toml"), options: .atomic)
            try Data(token.utf8).write(to: directory.appendingPathComponent("capability"), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("capability").path)
            let port = try localPort()
            let task = Process()
            task.executableURL = engine
            task.currentDirectoryURL = workspace
            task.arguments = ["app-server", "--listen", "ws://127.0.0.1:\(port)", "--ws-auth", "capability-token", "--ws-token-file", directory.appendingPathComponent("capability").path]
            // This is Codex's documented, dedicated account/config directory.
            task.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "CODEX_HOME": account.path,
                                "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8"]
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try task.run()
            defer { if task.isRunning { task.terminate() }; try? FileManager.default.removeItem(at: directory.appendingPathComponent("capability")) }
            var ready = false
            for _ in 0..<80 {
                if !task.isRunning { break }
                if listening(port) { ready = true; break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard ready else { throw Failure.socket }
            publish(["endpoint": "ws://127.0.0.1:\(port)", "workspace": workspace.path])
            while task.isRunning {
                Thread.sleep(forTimeInterval: 2)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("heartbeat").path),
                      let modified = attributes[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 45,
                      !FileManager.default.fileExists(atPath: directory.appendingPathComponent("stop").path)
                else { break }
            }
        } catch { publish(["error": "Codex could not start. Check the official CLI installation and reconnect."]) }
    }
    enum Failure: Error { case unsafePath, socket }
    static func secure(_ url: URL, mode: Int) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attrs[.type] as? FileAttributeType != .typeSymbolicLink,
              (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777 == mode else { return false }
        return true
    }
    static func trusted(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\" and identifier \"codex\"" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        return true
    }
    static func listening(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
    static func localPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.socket }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { throw Failure.socket }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else { throw Failure.socket }
        return UInt16(bigEndian: address.sin_port)
    }
}


private final class BridgeDelegate: NSObject, NSApplicationDelegate {
    private var started = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let argument = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("/") && UUID(uuidString: URL(fileURLWithPath: $0).lastPathComponent) != nil }) {
            begin(URL(fileURLWithPath: argument, isDirectory: true))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.started != true { NSApplication.shared.terminate(nil) }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.count == 1, let directory = urls.first, directory.isFileURL else { return }
        begin(directory)
    }
    private func begin(_ directory: URL) {
        guard !started else { return }
        started = true
        DispatchQueue.global(qos: .utility).async {
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
            MoonCodexBridge.runBridge(directory: directory)
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }
}

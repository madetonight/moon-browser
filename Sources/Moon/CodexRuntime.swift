import AppKit
import Foundation
import MoonCore
import Security

@MainActor
final class CodexRuntime {
    static let shared = CodexRuntime()
    struct Connection { let endpoint: URL; let token: String; let workspace: String }
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
    private var leases: Set<UUID> = []
    private var launch: Task<Connection, Error>?
    private var directory: URL?
    private var heartbeat: Task<Void, Never>?

    func acquire(_ id: UUID) async throws -> Connection {
        leases.insert(id)
        if let launch { return try await launch.value }
        let task = Task { try await start() }
        launch = task
        do { return try await task.value }
        catch { release(id); throw error }
    }
    func release(_ id: UUID) {
        leases.remove(id)
        guard leases.isEmpty else { return }
        shutdown()
    }
    func shutdown() {
        if let directory { try? Data().write(to: directory.appendingPathComponent("stop"), options: .atomic) }
        heartbeat?.cancel(); heartbeat = nil
        launch?.cancel(); launch = nil
        directory = nil
        leases = []
    }
    private func start() async throws -> Connection {
        let helpers = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers")
        guard
              FileManager.default.fileExists(atPath: helpers.appendingPathComponent("MoonCodexBridge.app").path)
        else { throw Failure.message("This build is missing the Codex companion. Install the latest Moon build.") }
        let folder = Store.folder.appendingPathComponent("Codex Bridge").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.deletingLastPathComponent().path)
        directory = folder
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw Failure.message("Could not create a private Codex connection.") }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let request = folder.appendingPathComponent("request.json")
        try JSONSerialization.data(withJSONObject: ["token": token]).write(to: request, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: request.path)
        try Data().write(to: folder.appendingPathComponent("heartbeat"), options: .atomic)
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, self?.directory == folder else { return }
                try? Data().write(to: folder.appendingPathComponent("heartbeat"), options: .atomic)
            }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.allowsRunningApplicationSubstitution = false
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            // Launch Services conveys access to this one generated connection
            // directory. The helper never searches Moon's protected container.
            NSWorkspace.shared.open([folder], withApplicationAt: helpers.appendingPathComponent("MoonCodexBridge.app"), configuration: configuration) { _, error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            }
        }
        for _ in 0..<100 {
            try Task.checkCancellation()
            if let data = try? Data(contentsOf: folder.appendingPathComponent("status.json")),
               let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = status["error"] as? String { throw Failure.message(error) }
                if let text = status["endpoint"] as? String, let endpoint = URL(string: text), CodexPolicy.endpoint(endpoint),
                   let workspace = status["workspace"] as? String {
                    // The engine may write its status just before it binds.
                    try await Task.sleep(for: .milliseconds(500))
                    return Connection(endpoint: endpoint, token: token, workspace: workspace)
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw Failure.message("Codex did not start. Install the official Codex CLI and reconnect.")
    }
}

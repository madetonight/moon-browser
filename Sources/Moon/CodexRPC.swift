import Foundation

/// One authenticated native connection. Credentials never enter a web view.
@MainActor
final class CodexRPC: NSObject, URLSessionTaskDelegate {
    var notification: ((String, [String: Any]) -> Void)?
    var serverRequest: ((Any, String, [String: Any]) -> Void)?
    var disconnected: (() -> Void)?
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var reader: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var serial = 0
    private var finished = false

    func connect(_ connection: CodexRuntime.Connection) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: connection.endpoint)
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 1_048_576
        self.socket = socket
        socket.resume()
        reader = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let frame = try await socket.receive()
                    let data: Data
                    switch frame {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    guard data.count <= 1_048_576,
                          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
                    self?.receive(object)
                }
            } catch {
                guard let self, !self.finished else { return }
                self.close()
                self.disconnected?()
            }
        }
    }
    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        guard !finished, socket != nil, pending.count < 32 else { throw URLError(.notConnectedToInternet) }
        serial += 1
        let id = serial
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            deadlines[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled, let self else { return }
                self.pending.removeValue(forKey: id)?.resume(throwing: URLError(.timedOut))
                self.deadlines.removeValue(forKey: id)
            }
            send(["id": id, "method": method, "params": params])
        }
    }
    func notify(_ method: String, _ params: [String: Any] = [:]) { send(["method": method, "params": params]) }
    func respond(_ id: Any, _ result: [String: Any]) { send(["id": id, "result": result]) }
    func refuse(_ id: Any) { send(["id": id, "error": ["code": -32601, "message": "This capability is unavailable in Moon."]]) }
    private func send(_ value: [String: Any]) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: value), data.count <= 1_048_576,
              let text = String(data: data, encoding: .utf8) else { return }
        let earlier = writer
        writer = Task {
            await earlier?.value
            guard !Task.isCancelled else { return }
            try? await socket.send(.string(text))
        }
    }
    private func receive(_ value: [String: Any]) {
        if let method = value["method"] as? String {
            let params = value["params"] as? [String: Any] ?? [:]
            if let id = value["id"] { serverRequest?(id, method, params) }
            else { notification?(method, params) }
            return
        }
        guard let id = value["id"] as? Int, let continuation = pending.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)?.cancel()
        if let error = value["error"] as? [String: Any] {
            continuation.resume(throwing: CodexRuntime.Failure.message(String((error["message"] as? String ?? "Codex request failed.").prefix(600))))
        } else { continuation.resume(returning: value["result"] as? [String: Any] ?? [:]) }
    }
    func close() {
        guard !finished else { return }
        finished = true
        reader?.cancel(); reader = nil
        writer?.cancel(); writer = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        session?.invalidateAndCancel(); session = nil
        for timer in deadlines.values { timer.cancel() }
        deadlines = [:]
        let waiting = pending; pending = [:]
        for continuation in waiting.values { continuation.resume(throwing: CancellationError()) }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

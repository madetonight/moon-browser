import Foundation

/// Google's native function-calling wire, using the same browser tool broker.
/// No key in URLs, no redirects, cookies, credentials or cached responses.
@MainActor
final class GeminiBrowserAgent: NSObject, URLSessionTaskDelegate {
    private var history: [[String: Any]] = []
    private let injectedNetwork: URLSession?
    init(network: URLSession? = nil) { injectedNetwork = network; super.init() }
    func close() { network.invalidateAndCancel(); history = [] }
    private lazy var network: URLSession = {
        if let injectedNetwork { return injectedNetwork }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    func models() async throws -> [String] {
        let response = try await call("models", body: nil)
        return (response["models"] as? [[String: Any]] ?? []).compactMap { model in
            guard (model["supportedGenerationMethods"] as? [String])?.contains("generateContent") == true,
                  let name = model["name"] as? String, name.hasPrefix("models/gemini-") else { return nil }
            return String(name.dropFirst(7))
        }.sorted()
    }
    func run(_ text: String, model: String, session: CodexSession) async throws {
        guard model.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil else { throw AIError.unreadable }
        history.append(["role": "user", "parts": [["text": text]]])
        for _ in 0..<12 {
            try Task.checkCancellation()
            let result = try await call("models/\(model):generateContent", body: [
                "contents": history,
                "systemInstruction": ["parts": [["text": CodexSession.browserInstructions]]],
                "tools": [["functionDeclarations": Self.declarations]],
                "generationConfig": ["maxOutputTokens": 4096]
            ])
            guard let candidate = (result["candidates"] as? [[String: Any]])?.first,
                  let content = candidate["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] else { throw AIError.unreadable }
            // Preserve model content, including thought signatures, exactly.
            history.append(content)
            let words = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
            if !words.isEmpty { session.appendAgentText(words) }
            let calls = parts.compactMap { $0["functionCall"] as? [String: Any] }
            if calls.isEmpty { return }
            var responses: [[String: Any]] = []
            for call in calls.prefix(12) {
                try Task.checkCancellation()
                guard let name = call["name"] as? String else { throw AIError.unreadable }
                var value: [String: Any]
                do { value = try await CodexBrowserTools.perform(name, call["args"] as? [String: Any] ?? [:], session: session) }
                catch { value = ["error": error.localizedDescription] }
                var response: [String: Any] = ["name": name, "response": value]
                if let id = call["id"] as? String { response["id"] = id }
                responses.append(["functionResponse": response])
            }
            history.append(["role": "user", "parts": responses])
            let size = try JSONSerialization.data(withJSONObject: history).count
            guard size < 600_000 else { throw AIError.unreachable("This conversation is full. Open a new assistant tab to continue.") }
        }
        throw AIError.unreachable("Reached this request's action limit. Ask to continue when you're ready.")
    }
    static var declarations: [[String: Any]] {
        CodexBrowserTools.specs.map { spec in
            let schema = spec["inputSchema"] as? [String: Any] ?? [:]
            let properties = (schema["properties"] as? [String: [String: Any]] ?? [:]).mapValues { property -> [String: Any] in
                var changed = property
                changed["type"] = (property["type"] as? String ?? "string").uppercased()
                return changed
            }
            return ["name": spec["name"]!, "description": spec["description"]!, "parameters": ["type": "OBJECT", "properties": properties, "required": schema["required"] ?? []]]
        }
    }
    private func call(_ path: String, body: [String: Any]?) async throws -> [String: Any] {
        guard let key = AIKeys.key(for: .gemini) else { throw AIError.noKey }
        let url = AIProvider.gemini.base.appendingPathComponent(path)
        guard AIClient.allowed(url, for: .gemini) else { throw AIError.refusedHost }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (bytes, response) = try await network.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw AIError.unreadable }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= 2_097_152 else { throw AIError.unreadable }
        }
        // Provider errors never echo a raw request or API key into the UI.
        guard (200..<300).contains(response.statusCode) else {
            throw AIError.http(response.statusCode, response.statusCode == 401 || response.statusCode == 403 ? "Check your Gemini key in Settings → AI." : "Gemini couldn't finish this request. Check your Google API quota and try again.")
        }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.unreadable }
        return value
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                               newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

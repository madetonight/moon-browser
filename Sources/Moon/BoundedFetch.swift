import Foundation
import MoonCore

/// Chunked background transfer with limits enforced before accumulating each chunk.
/// No cookies, credentials, disk cache, or redirects outside the chosen policy.
final class BoundedFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Body = (data: Data, response: HTTPURLResponse)
    private let lock = NSLock()
    private let policy: ResourcePolicy
    private let limit: Int
    private var bytes = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<Body, any Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var finished = false
    private var cancelled = false
    private init(policy: ResourcePolicy, limit: Int) { self.policy = policy; self.limit = limit }
    static func data(from url: URL, policy: ResourcePolicy, limit: Int, timeout: TimeInterval = 30) async throws -> Data {
        try await data(request: URLRequest(url: url), policy: policy, limit: limit, timeout: timeout)
    }
    static func data(request: URLRequest, policy: ResourcePolicy, limit: Int, timeout: TimeInterval = 30) async throws -> Data {
        try await body(request: request, policy: policy, limit: limit, timeout: timeout).data
    }
    static func body(request: URLRequest, policy: ResourcePolicy, limit: Int, timeout: TimeInterval) async throws -> Body {
        guard let url = request.url else { throw URLError(.badURL) }
        guard limit > 0, policy.allows(url) else { throw URLError(.unsupportedURL) }
        let transfer = BoundedFetch(policy: policy, limit: limit)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.lock.lock()
                guard !transfer.cancelled else { transfer.lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                transfer.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil
                configuration.urlCredentialStorage = nil; configuration.urlCache = nil
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
                configuration.timeoutIntervalForRequest = min(timeout, 30); configuration.timeoutIntervalForResource = timeout
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
                let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: queue)
                transfer.session = session
                let task = session.dataTask(with: request); transfer.task = task
                transfer.lock.unlock(); task.resume()
            }
        } onCancel: { transfer.cancel() }
    }
    private func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, policy.allows(url) else {
            completionHandler(nil); finish(.failure(URLError(.redirectToNonExistentLocation))); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, let url = response.url,
              policy.allows(url), policy.allows(status: response.statusCode) else {
            completionHandler(.cancel); finish(.failure(URLError(.badServerResponse))); return
        }
        guard response.expectedContentLength <= limit else {
            completionHandler(.cancel); finish(.failure(URLError(.dataLengthExceedsMaximum))); return
        }
        lock.lock(); self.response = response; lock.unlock()
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard data.count <= limit - bytes.count else { lock.unlock(); finish(.failure(URLError(.dataLengthExceedsMaximum))); return }
        bytes.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)) }
        else {
            lock.lock(); let body = response.map { (data: bytes, response: $0) }; lock.unlock()
            finish(body.map(Result.success) ?? .failure(URLError(.badServerResponse)))
        }
    }
    private func finish(_ result: Result<Body, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation, session = session
        self.continuation = nil; self.session = nil; task = nil; bytes = Data(); response = nil
        lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
}

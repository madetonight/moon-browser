import Foundation
import MoonCore

/// Chunked background transfer with limits enforced before accumulating each chunk.
/// No cookies, credentials, disk cache, or redirects outside the chosen policy.
final class BoundedFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let policy: ResourcePolicy
    private let limit: Int
    private var bytes = Data()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var finished = false
    private var cancelled = false
    private init(policy: ResourcePolicy, limit: Int) { self.policy = policy; self.limit = limit }
    static func data(from url: URL, policy: ResourcePolicy, limit: Int, timeout: TimeInterval = 30) async throws -> Data {
        guard policy.allows(url) else { throw URLError(.unsupportedURL) }
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
                let task = session.dataTask(with: url); transfer.task = task
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
        guard let response = response as? HTTPURLResponse, let url = response.url, policy.allows(url), response.statusCode == 200,
              response.expectedContentLength <= limit else {
            completionHandler(.cancel); finish(.failure(URLError(.badServerResponse))); return
        }
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
            lock.lock(); let data = bytes; lock.unlock()
            finish(.success(data))
        }
    }
    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation, session = session
        self.continuation = nil; self.session = nil; task = nil; bytes = Data()
        lock.unlock()
        session?.invalidateAndCancel(); continuation?.resume(with: result)
    }
}

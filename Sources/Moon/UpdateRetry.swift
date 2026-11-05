import Foundation
import Sparkle

/// Only transport failures can be retried. Signature, certificate, feed-format
/// and installation failures remain terminal and keep Sparkle's protections.
struct UpdateRetry {
    private(set) var attempts = 0

    mutating func reset() { attempts = 0 }

    mutating func nextDelay(for error: NSError) -> TimeInterval? {
        guard attempts < 2, Self.isTransient(error) else { return nil }
        defer { attempts += 1 }
        return attempts == 0 ? 3 : 15
    }

    static func isTransient(_ error: NSError) -> Bool {
        var current = error
        for _ in 0..<8 {
            if current.domain == NSURLErrorDomain {
                return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                        NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                        NSURLErrorDNSLookupFailed, NSURLErrorCannotFindHost].contains(current.code)
            }
            guard current.domain == SUSparkleErrorDomain,
                  [Int(SUError.downloadError.rawValue), Int(SUError.appcastError.rawValue)].contains(current.code),
                  let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
            else { return false }
            current = underlying
        }
        return false
    }
}

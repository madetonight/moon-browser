import AppKit
import Sparkle
import WebKit
import XCTest
@testable import Moon

@MainActor
final class LoadingRecoveryTests: XCTestCase {
    override class func setUp() {
        setenv("MOON_PROBE", "loading-recovery-\(getpid())", 1)
        super.setUp()
    }

    func testNestedUpdateOfflineFailureHasABoundedRetryBudget() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let download = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.downloadError.rawValue),
                               userInfo: [NSUnderlyingErrorKey: offline])
        let feed = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.appcastError.rawValue),
                           userInfo: [NSUnderlyingErrorKey: download])
        var retry = UpdateRetry()
        XCTAssertEqual(retry.nextDelay(for: feed), 3)
        XCTAssertEqual(retry.nextDelay(for: feed), 15)
        XCTAssertNil(retry.nextDelay(for: feed), "A broken network must not cause an endless check loop")
        retry.reset()
        XCTAssertEqual(retry.nextDelay(for: feed), 3)
    }

    func testCertificateSignatureAndInstallationErrorsAreNeverRetried() {
        let network = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        for code in [Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue),
                     Int(SUError.installationError.rawValue), Int(SUError.appcastParseError.rawValue)] {
            let failure = NSError(domain: SUSparkleErrorDomain, code: code,
                                  userInfo: [NSUnderlyingErrorKey: network])
            XCTAssertFalse(UpdateRetry.isTransient(failure))
        }
        for code in [NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed,
                     NSURLErrorCancelled, NSURLErrorUserAuthenticationRequired] {
            XCTAssertFalse(UpdateRetry.isTransient(NSError(domain: NSURLErrorDomain, code: code)))
        }
        XCTAssertFalse(UpdateRetry.isTransient(NSError(domain: "other", code: NSURLErrorTimedOut)))
    }

    func testOldFailuresCannotCoverANewerNavigation() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let tab = try XCTUnwrap(browser.tabs.last)
        tab.restore(url: URL(string: "about:blank")!, title: "Fixture")
        let view = tab.web
        view.navigationDelegate = nil
        let old = try XCTUnwrap(view.loadHTMLString("<title>Old</title>", baseURL: nil))
        let next = try XCTUnwrap(view.loadHTMLString("<title>New</title>", baseURL: nil))
        browser.webView(view, didStartProvisionalNavigation: old)
        tab.failure = "Earlier failure"
        browser.webView(view, didStartProvisionalNavigation: next)
        XCTAssertNil(tab.failure, "A fresh navigation clears the old error immediately")
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        browser.webView(view, didFailProvisionalNavigation: old, withError: timeout)
        browser.webView(view, didFail: old, withError: timeout)
        XCTAssertNil(tab.failure)
        browser.webView(view, didFailProvisionalNavigation: next, withError: timeout)
        XCTAssertEqual(tab.failure, "The site took too long to answer.")
        browser.webView(view, didCommit: old)
        XCTAssertNotNil(tab.failure, "An obsolete commit must not clear the current failure")
        tab.cover(with: NSImage(size: NSSize(width: 40, height: 40)))
        browser.webView(view, didFinish: old)
        XCTAssertNotNil(tab.cover, "An obsolete finish must not change the current page's presentation")
    }

    func testExplicitNavigationRejectsOldCallbacksBeforeWebKitStarts() throws {
        _ = NSApplication.shared
        let tab = Tab(configuration: Web.configuration(shy: true))
        defer { tab.close() }
        let old = try XCTUnwrap(tab.web.loadHTMLString("old", baseURL: nil))
        tab.navigationLifecycle.started(old)
        XCTAssertTrue(tab.navigationLifecycle.accepts(old))
        tab.go(to: URL(string: "about:blank#new")!)
        XCTAssertFalse(tab.navigationLifecycle.accepts(old))
        XCTAssertFalse(tab.navigationLifecycle.accepts(nil))
    }
}

import AppKit
import WebKit

/// Explicit, disposable native integration fixtures; never the normal profile.
@MainActor enum MoonSmoke {
    static func startIfNeeded() {
        guard CommandLine.arguments.contains("--smoke-test"), Store.testing,
              let origin = ProcessInfo.processInfo.environment["MOON_FIXTURE_ORIGIN"].flatMap(URL.init(string:)),
              origin.host() == "127.0.0.1" else { return }
        Task {
            var checks: [String: Bool] = [:]
            do {
                let browser = SceneSlot.shared.browser
                if ProcessInfo.processInfo.environment["MOON_SECURITY_FIXTURE"] == "1" {
                    try await securityChecks(browser, into: &checks)
                }
                checks["test_profile_isolated"] = Store.testing && (SandboxAccess.enabled || Store.folder.path.hasPrefix("/private/tmp/"))
                let lazy = Tab()
                checks["unopened_tab_has_no_webview"] = lazy.built == nil
                checks["safari_configuration"] = Web.configuration().applicationNameForUserAgent == Web.userAgentName
                let tab = browser.benchOpen(origin.appendingPathComponent("page"))
                try await wait { tab.built?.title == "Moon 1.0.7 fixture" && !tab.loading }
                let web = tab.web
                let ua = try await web.evaluateJavaScript("navigator.userAgent") as? String ?? ""
                checks["actual_page_has_safari_identity"] = ua.contains(Web.userAgentName)
                checks["page_cannot_access_password_bridge"] = (try await web.evaluateJavaScript("typeof window.webkit?.messageHandlers?.officeForms") as? String) == "undefined"
                checks["page_cannot_access_native_form_globals"] = (try await web.evaluateJavaScript("typeof window.__officeForms") as? String) == "undefined"
                checks["page_cannot_access_draft_bridge"] = (try await web.evaluateJavaScript("typeof window.webkit?.messageHandlers?.moonDirty") as? String) == "undefined"
                checks["modern_dom_loaded"] = (try await web.evaluateJavaScript("document.querySelector('#modern')?.textContent") as? String) == "Modern WebKit"
                tab.go(to: origin.appendingPathComponent("login"))
                try await wait { !tab.loading && tab.web.title == "Moon login fixture" }
                let denied = await withCheckedContinuation { c in
                    tab.fill(user: "synthetic-user", password: "synthetic-password", onlyOn: URL(string: "https://unrelated.example.test/")) { c.resume(returning: $0) }
                }
                let untouched = try await web.evaluateJavaScript("document.querySelector('#password').value") as? String
                checks["password_fill_rejects_wrong_site"] = !denied && untouched == ""
                let accepted = await withCheckedContinuation { c in
                    tab.fill(user: "synthetic-user", password: "synthetic-password", onlyOn: origin) { c.resume(returning: $0) }
                }
                let filled = try await web.evaluateJavaScript("document.querySelector('#password').value") as? String
                checks["explicit_matching_site_fill_works"] = accepted && filled == "synthetic-password"
                // Filled values belong to the selected page's DOM. No Keychain item is used.
                checks["password_global_is_not_exposed"] = (try await web.evaluateJavaScript("typeof window.passwords") as? String) == "undefined"
                tab.go(to: origin.appendingPathComponent("page"))
                try await wait { !tab.loading && tab.web.title == "Moon 1.0.7 fixture" }
                // Same-origin and cross-origin frames must both retain drafts.
                try await web.callAsyncJavaScript("window.__moonMarkDirty()", arguments: [:], in: nil, contentWorld: Web.world)
                try await wait { !tab.moonDirtyFrames.isEmpty }
                checks["native_draft_marker_received"] = !tab.moonDirtyFrames.isEmpty
                checks["unsaved_draft_blocks_sleep"] = await withCheckedContinuation { c in tab.unsaved { c.resume(returning: $0) } }
                tab.go(to: origin.appendingPathComponent("clean"))
                try await wait { tab.web.title == "Moon clean fixture" && !tab.loading }
                checks["new_document_clears_draft_cache"] = tab.moonDirtyFrames.isEmpty && !tab.moonDirtyOverflow
                let privateTab = browser.benchOpen(origin.appendingPathComponent("clean"), shy: true)
                checks["private_store_nonpersistent"] = !privateTab.store.isPersistent
                checks["private_view_has_no_extensions"] = privateTab.web.configuration.webExtensionController == nil
                try await wait { !privateTab.loading && privateTab.web.title == "Moon clean fixture" }
                checks["private_page_loads"] = privateTab.web.title == "Moon clean fixture"
                let session = Session.Shape(tabs: [Session.Entry(url: origin.absoluteString, title: "Fixture", pin: nil)], active: 0)
                Session.write(now: true, space: Space.firstID, session)
                checks["session_roundtrip"] = Session.read().tabs.first?.url == origin.absoluteString
                checks["moon_internal_pages"] = InternalPage(url: URL(string: "moon://settings/appearance")!)?.kind == .settings
                checks["all_settings_ids_unique"] = Set(SettingsIndex.items.map(\.id)).count == SettingsIndex.items.count
                checks["glass_setting_is_searchable"] = SettingsIndex.item("appearance.glass") != nil
                checks["ollama_only"] = AIProvider.allCases == [.ollama]
                checks["translation_available"] = PageTranslator.available
                // Actual MV3 worker/content-script/storage/messages through the port's host.
                tab.go(to: origin.appendingPathComponent("extension"))
                try await wait(seconds: 25) {
                    (try? await web.evaluateJavaScript("document.documentElement.dataset.moonExtension")) as? String == "ready"
                }
                checks["mv3_worker_storage_message_content_script"] = true
                let fixture = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab"
                checks["extension_loaded_by_moon_host"] = Extensions.shared.contexts[fixture] != nil
                checks["private_tab_still_excludes_extension"] = privateTab.web.configuration.webExtensionController == nil
                browser.close(tab); browser.close(privateTab)
            } catch {
                checks["fixture_completed"] = false
                try? Data(String(describing: error).utf8).write(to: Store.file("smoke-error.txt"))
            }
            let report: [String: Any] = ["passed": !checks.values.contains(false), "checks": checks,
                "failures": checks.filter { !$0.value }.map(\.key), "source": "Search v1.0.7 / Moon port", "date": ISO8601DateFormatter().string(from: Date())]
            if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? bytes.write(to: Store.file("report.json"), options: .atomic)
            }
            NSApp.terminate(nil)
        }
    }

    private static func securityChecks(_ browser: Browser, into checks: inout [String: Bool]) async throws {
        checks["app_sandbox_entitlement"] = SandboxAccess.enabled
        checks["updates_cannot_report_unpublished_feed_as_current"] = Updater.shared.configurationIssue != nil
        if let path = ProcessInfo.processInfo.environment["MOON_OUTSIDE_CANARY"] {
            let file = URL(fileURLWithPath: path)
            checks["sandbox_blocks_outside_read"] = (try? Data(contentsOf: file)) == nil
            do { try Data("modified".utf8).write(to: file); checks["sandbox_blocks_outside_write"] = false }
            catch { checks["sandbox_blocks_outside_write"] = true }
        } else { checks["sandbox_blocks_outside_read"] = false }
        let folder = Store.file("Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        browser.prefs.downloads = folder
        browser.prefs.asksWhereToSave = false
        browser.loot.forgetAll()
        let config = Web.configuration()
        config.websiteDataStore = .nonPersistent()
        let privateView = WKWebView(frame: .zero, configuration: config)
        let bytes = Data("%PDF-1.7\nMoon harmless security fixture".utf8)
        browser.webView(privateView, saveDataToFile: bytes, suggestedFilename: "../../private.pdf", mimeType: "application/pdf", originatingURL: URL(string: "https://private.example.test/secret"))
        checks["private_pdf_saved_inside_destination"] = (try? Data(contentsOf: folder.appendingPathComponent("private.pdf"))) == bytes
        Disk.drain()
        checks["private_pdf_no_persisted_metadata"] = Loot().kept.isEmpty && browser.loot.kept.isEmpty
        let record = Store.file("sandbox-owner-check.json")
        Disk.write(record, now: true) { Data("{}".utf8) }
        checks["metadata_owner_only"] = ((try FileManager.default.attributesOfItem(atPath: record.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0
        let privateFile = folder.appendingPathComponent("private.pdf")
        privateView.open(privateFile)
        checks["private_local_file_has_no_persistent_bookmark"] = Store.settings.dictionary(forKey: "sandbox.fileBookmarks")?[privateFile.standardizedFileURL.path] == nil
        let ordinaryView = WKWebView(frame: .zero, configuration: Web.configuration())
        browser.webView(ordinaryView, saveDataToFile: bytes, suggestedFilename: "regular.pdf", mimeType: "application/pdf", originatingURL: URL(string: "https://ordinary.example.test/file"))
        Disk.drain()
        checks["regular_pdf_keeps_metadata"] = Loot().kept.contains { $0.name == "regular.pdf" && $0.from == "ordinary.example.test" }
        checks["direct_pdf_quarantined"] = getxattr(folder.appendingPathComponent("regular.pdf").path, "com.apple.quarantine", nil, 0, 0, 0) > 0
        if let text = ProcessInfo.processInfo.environment["MOON_TLS_FIXTURE"], let url = URL(string: text) {
            let tab = browser.benchOpen(url)
            try await wait { tab.failure != nil }
            checks["self_signed_local_https_rejected"] = tab.web.title != "Moon untrusted TLS fixture" && tab.failure != nil
            browser.close(tab)
        } else { checks["self_signed_local_https_rejected"] = false }
        checks["bench_socket_fits_platform_limit"] = Bench.socket.path.utf8.count < 104
        browser.loot.forgetAll()
    }

    private static func wait(seconds: Double = 15, _ condition: () async throws -> Bool) async throws {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "MoonSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Native fixture timed out"])
    }
}

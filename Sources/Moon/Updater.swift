import AppKit
import Combine
import Network
import Security
import Sparkle

/// Background checks and install-on-quit, using a signed sandbox installer.
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updater()
    nonisolated static let installKey = "update.install"
    nonisolated static let team = Bundle.main.object(forInfoDictionaryKey: "MoonReleaseTeam") as? String ?? ""
    nonisolated static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
    nonisolated static var build: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }
    nonisolated static var feed: URL {
        URL(string: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "https://raw.githubusercontent.com/madetonight/moon-browser/main/appcast.xml")!
    }
    struct Release: Equatable {
        let version: String
        let build: Int
        let archive: URL
        let dmg: URL
        let sha256: String?
        var dmgSha256: String? = nil
        let notes: String?
        let minimumSystemVersion: String?
        var runsHere: Bool {
            guard let minimumSystemVersion else { return true }
            let parts = minimumSystemVersion.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                  let major = Int(parts[0]), major > 0 else { return false }
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: major,
                minorVersion: parts.count > 1 ? Int(parts[1]) ?? 0 : 0,
                patchVersion: parts.count > 2 ? Int(parts[2]) ?? 0 : 0))
        }
    }
    enum Stage: Equatable {
        case none, fetching(Release), ready(Release), offered(Release), waiting(Release)
    }
    @Published private(set) var stage: Stage = .none
    @Published private(set) var checking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var status = "Signed releases are not published yet"
    private(set) var fetchingDisk = false
    static var diskVerdict = "The legacy disk-image updater is disabled"
    private var controller: SPUStandardUpdaterController?
    private var installAndRelaunch: (() -> Void)?
    private var completion: ((Release?) -> Void)?
    private var say: ((String) -> Void)?
    private var bag: Set<AnyCancellable> = []
    private var retry = UpdateRetry()
    private var retryTask: Task<Void, Never>?
    private var pendingTransportError: NSError?
    private var networkAvailable = true
    private var networkMonitor: NWPathMonitor?

    /// A missing feed or failed check must never be reported as up to date.
    nonisolated static func configurationProblem(_ info: [String: Any]) -> String? {
        guard let url = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            return "Updates require a secure HTTPS feed"
        }
        guard let text = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: text)?.count == 32 else { return "The update signing key is not configured" }
        guard info["MoonUpdateFeedReady"] as? Bool == true else { return "Signed releases are not published yet" }
        guard info["SURequireSignedFeed"] as? Bool == true,
              info["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              info["SUSignedFeedFailureExpirationInterval"] as? Int == 0 else {
            return "Update signature protections are not configured"
        }
        return nil
    }
    var configurationIssue: String? { Self.configurationProblem(Bundle.main.infoDictionary ?? [:]) }
    private override init() { super.init() }

    func checkIfDue(then say: @escaping (String) -> Void) {
        self.say = say
        start()
    }
    private func start() {
        guard controller == nil else { return }
        guard !Store.testing else { status = "Updates are isolated from test runs"; return }
        if let issue = configurationIssue { status = issue; return }
        let candidate = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do {
            try candidate.updater.start()
            controller = candidate
            status = "Signed updates checked every hour"
            candidate.updater.publisher(for: \.sessionInProgress)
                .receive(on: DispatchQueue.main).assign(to: &$checking)
            candidate.updater.publisher(for: \.sessionInProgress)
                .receive(on: DispatchQueue.main).sink { [weak self] busy in
                    if !busy { self?.scheduleTransportRetry() }
                }.store(in: &bag)
            candidate.updater.publisher(for: \.lastUpdateCheckDate)
                .receive(on: DispatchQueue.main).assign(to: &$lastChecked)
            applyAutomaticPreference()
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                let available = path.status == .satisfied
                Task { @MainActor [weak self] in
                    self?.networkAvailable = available
                    if available { self?.scheduleTransportRetry() }
                }
            }
            monitor.start(queue: DispatchQueue(label: "org.moonbrowser.update-connectivity", qos: .utility))
            networkMonitor = monitor
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.applyAutomaticPreference() }.store(in: &bag)
        } catch { status = "Updates could not start: \(error.localizedDescription)" }
    }
    private func applyAutomaticPreference() {
        let enabled = Store.settings.object(forKey: Self.installKey) as? Bool ?? true
        if controller?.updater.automaticallyDownloadsUpdates != enabled {
            controller?.updater.automaticallyDownloadsUpdates = enabled
        }
    }
    func checkByHand() {
        start()
        guard let controller else { say?(status); return }
        guard controller.updater.canCheckForUpdates else {
            say?("An update check or installation is already in progress")
            return
        }
        clearTransportRetry(reset: true)
        controller.checkForUpdates(nil)
    }
    func check(then done: @escaping (Release?) -> Void) {
        start()
        guard let controller, controller.updater.canCheckForUpdates else { say?(status); done(nil); return }
        completion = done
        controller.updater.checkForUpdateInformation()
    }
    func install() { checkByHand() }
    func relaunch() {
        guard let installAndRelaunch else { checkByHand(); return }
        installAndRelaunch()
    }
    func openDisk() { checkByHand() }
    private func release(_ item: SUAppcastItem) -> Release {
        Release(version: item.displayVersionString, build: Int(item.versionString) ?? 0,
                archive: item.fileURL ?? Self.feed, dmg: item.fileURL ?? Self.feed,
                sha256: nil, notes: nil, minimumSystemVersion: item.minimumSystemVersion)
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        clearTransportRetry(reset: false)
        let next = release(item)
        stage = updater.automaticallyDownloadsUpdates ? .fetching(next) : .waiting(next)
        status = "Moon \(next.version) is available"
        completion?(next); completion = nil
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        clearTransportRetry(reset: true)
        stage = .none; status = "Moon is up to date"
        completion?(nil); completion = nil
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Sparkle ends an ordinary "no update" cycle with this sentinel too.
        // didNotFindUpdate already supplied the successful result.
        let failure = error as NSError
        if failure.domain == SUSparkleErrorDomain, failure.code == Int(SUError.noUpdateError.rawValue) { return }
        clearTransportRetry(reset: false)
        stage = .none
        installAndRelaunch = nil
        status = "Update check failed: \(error.localizedDescription)"
        completion?(nil); completion = nil
        if UpdateRetry.isTransient(error as NSError) {
            pendingTransportError = error as NSError
            status = "Update connection interrupted — retrying when connected"
            scheduleTransportRetry()
        }
    }
    private func clearTransportRetry(reset: Bool) {
        retryTask?.cancel()
        retryTask = nil
        pendingTransportError = nil
        if reset { retry.reset() }
    }
    private func scheduleTransportRetry() {
        guard !Store.testing, networkAvailable, retryTask == nil,
              let error = pendingTransportError,
              let updater = controller?.updater, updater.canCheckForUpdates else { return }
        guard let delay = retry.nextDelay(for: error) else {
            pendingTransportError = nil
            status = "Update connection failed. Check your connection and try again."
            return
        }
        // Sleeping suspends this task; only Sparkle's UI-bound state is used
        // on the main actor. Never replace its downloader or signature checks.
        retryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            retryTask = nil
            guard networkAvailable, updater.canCheckForUpdates else { return }
            pendingTransportError = nil
            status = "Retrying the signed update check"
            updater.checkForUpdatesInBackground()
        }
    }
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        stage = .ready(release(item))
        installAndRelaunch = immediateInstallationBlock
        status = "Moon \(item.displayVersionString) is ready for the next launch"
        say?(status)
        return true
    }
    /// The custom ZIP-feed/self-swap path has been removed.
    nonisolated static func opened(_ packed: Data) -> Data? { nil }
    /// Also used by the disabled bundled AI-engine verifier.
    nonisolated static func developerID(team: String, identifier: String?) -> SecRequirement? {
        guard team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil,
              identifier.map({ $0.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil }) ?? true else { return nil }
        let text = "anchor apple generic" + (identifier.map { " and identifier \"\($0)\"" } ?? "")
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }
}

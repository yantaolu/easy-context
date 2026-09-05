import AppKit
import Combine
import Foundation
import EasyContextCore

@MainActor
final class UpdateController: ObservableObject {
    enum UpdateAlert: Identifiable, Equatable {
        case upToDate
        case available(EasyContextRelease)
        case failed(UpdateCheckFailure)

        var id: String {
            switch self {
            case .upToDate: return "up-to-date"
            case .available(let release): return "available-\(release.tag)"
            case .failed(let failure): return "failed-\(String(describing: failure))"
            }
        }
    }

    @Published private(set) var isChecking = false
    @Published var presentedAlert: UpdateAlert?

    let productVersion: String
    let buildNumber: String

    private let service: UpdateCheckService
    private let openURL: (URL) -> Void
    private var checkTask: Task<Void, Never>?
    private var requestGeneration: UInt64 = 0

    convenience init(bundle: Bundle = .main,
                     defaults: UserDefaults = .standard,
                     client: any LatestReleaseFetching = GitHubLatestReleaseClient(),
                     now: @escaping @MainActor @Sendable () -> Date = { Date() },
                     openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.init(
            productVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—",
            defaults: defaults,
            client: client,
            now: now,
            openURL: openURL)
    }

    init(productVersion: String,
         buildNumber: String,
         defaults: UserDefaults,
         client: any LatestReleaseFetching,
         now: @escaping @MainActor @Sendable () -> Date = { Date() },
         openURL: @escaping (URL) -> Void) {
        self.productVersion = productVersion
        self.buildNumber = buildNumber
        let storage = UserDefaultsUpdateStorage(defaults: defaults)
        service = UpdateCheckService(client: client, storage: storage, now: now)
        self.openURL = openURL
    }

    func checkManually() {
        guard !isChecking else { return }
        requestGeneration &+= 1
        let generation = requestGeneration
        presentedAlert = nil
        isChecking = true
        checkTask = Task { [weak self] in
            guard let self else { return }
            let disposition = await service.check(currentVersion: productVersion, trigger: .manual)
            guard !Task.isCancelled, requestGeneration == generation else { return }
            isChecking = false
            checkTask = nil
            switch disposition {
            case .completed(.updateAvailable(let release)):
                presentedAlert = .available(release)
            case .completed(.upToDate):
                presentedAlert = .upToDate
            case .completed(.failed(let failure)):
                presentedAlert = .failed(failure)
            case .skipped:
                // 手动检查当前不会走到 skipped；保守转换为可见失败。
                presentedAlert = .failed(.network)
            }
        }
    }

    /// 设置窗关闭或更新视图离场时，所有晚到结果都失去 UI 呈现资格。
    func cancelPresentation() {
        requestGeneration &+= 1
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
        presentedAlert = nil
        // Core 最多 10 秒的同端点请求继续收尾；下次点击可安全复用，避免重复请求和状态竞争。
    }

    func openRelease(_ release: EasyContextRelease) {
        presentedAlert = nil
        guard release.isTrusted else { return }
        openURL(release.pageURL)
    }
}

@MainActor
private final class UserDefaultsUpdateStorage: UpdateCheckStorage {
    private enum Key {
        static let automaticChecksEnabled = "updates.automaticChecksEnabled"
        static let lastAttempt = "updates.lastAttempt"
        static let lastSuccessfulCheck = "updates.lastSuccessfulCheck"
        static let automaticRetryAfter = "updates.automaticRetryAfter"
        static let serverRetryAfter = "updates.serverRetryAfter"
        static let cachedRelease = "updates.cachedRelease"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var automaticChecksEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.automaticChecksEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.automaticChecksEnabled)
        }
        set { defaults.set(newValue, forKey: Key.automaticChecksEnabled) }
    }

    var lastSuccessfulCheck: Date? {
        get { defaults.object(forKey: Key.lastSuccessfulCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSuccessfulCheck) }
    }

    var lastAttempt: Date? {
        get { defaults.object(forKey: Key.lastAttempt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastAttempt) }
    }

    var automaticRetryAfter: Date? {
        get { defaults.object(forKey: Key.automaticRetryAfter) as? Date }
        set { defaults.set(newValue, forKey: Key.automaticRetryAfter) }
    }

    var serverRetryAfter: Date? {
        get { defaults.object(forKey: Key.serverRetryAfter) as? Date }
        set { defaults.set(newValue, forKey: Key.serverRetryAfter) }
    }

    var cachedRelease: EasyContextRelease? {
        get {
            guard let data = defaults.data(forKey: Key.cachedRelease),
                  let release = try? JSONDecoder().decode(EasyContextRelease.self, from: data),
                  release.isTrusted else {
                defaults.removeObject(forKey: Key.cachedRelease)
                return nil
            }
            return release
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.cachedRelease)
                return
            }
            guard newValue.isTrusted, let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.cachedRelease)
        }
    }
}

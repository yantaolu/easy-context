import AppKit
import Security
import EasyContextCore

/// 外置磁盘访问授权（macOS 隐私授权「可移除宗卷」）。
///
/// Finder 扩展是后台进程，macOS 不会为它弹出授权询问，未授权时访问被直接拒绝；
/// 但扩展的授权归属于宿主 bundle id。因此由前台的宿主读取一次外置盘来触发询问，
/// 允许后扩展随之可用。该授权按「签名身份」保存：固定证书签名的升级之间保持有效，
/// 签名身份变化时安装器会重置它——这里同样按签名身份记住「已获授权」。
@MainActor
final class VolumeAccess: ObservableObject {
    static let shared = VolumeAccess()

    enum State: Equatable {
        case notNeeded   // 没有外置盘，或当前签名身份已获授权
        case needsAccess // 有外置盘、尚未确认授权
        case requesting  // 正在等待系统询问的结果
        case denied      // 用户拒绝过（系统不会再询问，需到系统设置开启）
    }

    @Published private(set) var state: State = .notNeeded

    private static let grantedKey = "volumeAccess.grantedRequirement"
    private static let privacySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    private let defaults = UserDefaults.standard
    private let identity = VolumeAccess.currentDesignatedRequirement()
    private var observers: [NSObjectProtocol] = []

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        // 从系统设置开启授权后回到 App：已拒绝状态下静默复查（已作答过，不会再弹询问）。
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .denied else { return }
                self.requestAccess()
            }
        })
        refresh()
    }

    private var isGrantedForCurrentIdentity: Bool {
        guard let identity else { return false }
        return defaults.string(forKey: Self.grantedKey) == identity
    }

    func refresh() {
        guard state != .requesting else { return }
        if isGrantedForCurrentIdentity || ExternalVolumes.mounted().isEmpty {
            state = .notNeeded
        } else if state != .denied {
            state = .needsAccess
        }
    }

    /// 读取一个外置盘的根目录：授权未决定时触发系统询问（后台线程上阻塞到用户作答）。
    func requestAccess() {
        guard state != .requesting else { return }
        guard let volume = ExternalVolumes.mounted().first else {
            state = .notNeeded
            return
        }
        state = .requesting
        NSApp.activate(ignoringOtherApps: true)
        let path = volume.path
        Task {
            let result = await Task.detached(priority: .userInitiated) { FolderAccessProbe.probe(path) }.value
            record(result)
        }
    }

    /// 打开失败的兜底流程读取了某个目录：若它在外置盘上，同步更新授权状态。
    func noteProbe(_ result: FolderAccessProbe, path: String) {
        let onExternal = ExternalVolumes.mounted().contains { volume in
            path == volume.path || path.hasPrefix(volume.path + "/")
        }
        guard onExternal else { return }
        record(result)
    }

    func openPrivacySettings() {
        if let url = Self.privacySettingsURL { NSWorkspace.shared.open(url) }
    }

    private func record(_ result: FolderAccessProbe) {
        switch result {
        case .granted:
            if let identity { defaults.set(identity, forKey: Self.grantedKey) }
            state = .notNeeded
        case .denied:
            defaults.removeObject(forKey: Self.grantedKey)
            state = .denied
        case .failed:
            // 卷在读取期间被卸载等：不改变授权判断，按当前挂载情况重算。
            if state == .requesting { state = .needsAccess }
            refresh()
        }
    }

    /// 本进程的 designated requirement 文本；与安装器判断「签名身份是否变化」同一口径。
    private static func currentDesignatedRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
    }
}

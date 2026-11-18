import AppKit
import EasyContextCore

/// 处理扩展发来的 `open-error`：扩展用 LaunchServices 打开目录失败（最常见是外置盘、
/// 桌面等受隐私授权保护的位置未获授权——后台扩展无法触发系统询问）。
///
/// 宿主在前台逐个读取目录：授权未决定时系统会弹出询问；获准后由宿主（非沙盒）用同一个
/// App 打开这些目录。用户拒绝时说明如何到系统设置开启。
enum FolderOpenRecovery {
    /// 询问或打开进行中再收到请求则忽略，避免叠出多个询问 / 弹窗。
    @MainActor private static var inFlight = false

    @MainActor
    static func handle(_ url: URL) {
        let store = ConfigStore()
        let token = store.readIPCToken()
        // token 不符：伪造或过期请求，静默忽略（与其它 IPC 入口一致）。
        guard !token.isEmpty,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "t" })?.value == token
        else { return }
        guard let failure = FolderOpenFailure(url: url, scheme: IPCScheme.current, expectedToken: token) else {
            // 缺少目标 App / 目录（例如升级期间尚未重启的旧版扩展）：只能给出通用说明。
            alert(String(localized: "The application could not open the folder. See the EasyContext directory open failed entry in Console for the system error."))
            return
        }
        // 只替用户已配置或内置识别的 App 打开目录，不接受任意 bundle id。
        let settings = store.load()
        let allowed = Set((settings.terminals + settings.editors).map(\.bundleId)
                          + (KnownApps.terminals + KnownApps.editors).map(\.bundleId))
        guard allowed.contains(failure.appBundleId),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: failure.appBundleId)
        else { return }
        let directories = failure.directories.filter { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
        guard !directories.isEmpty, !inFlight else { return }

        inFlight = true
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            defer { inFlight = false }
            for path in directories {
                let result = await Task.detached(priority: .userInitiated) { FolderAccessProbe.probe(path) }.value
                VolumeAccess.shared.noteProbe(result, path: path)
                if result == .denied {
                    showDenied(path)
                    return
                }
            }
            let urls = directories.map { URL(fileURLWithPath: $0, isDirectory: true) }
            NSWorkspace.shared.open(urls, withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                guard let error else { return }
                Task { @MainActor in alert(error.localizedDescription) }
            }
        }
    }

    @MainActor
    private static func showDenied(_ path: String) {
        let name = FileManager.default.displayName(atPath: path)
        let alert = NSAlert()
        alert.messageText = String(localized: "Could Not Open Folder")
        alert.informativeText = String(localized: "macOS denied Easy Context access to “\(name)”. Turn on Easy Context in System Settings → Privacy & Security → Files and Folders, then try again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            VolumeAccess.shared.openPrivacySettings()
        }
    }

    @MainActor
    private static func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Could Not Open Folder")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

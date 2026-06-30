import Foundation
import AppKit
import FinderSync
import EasyContextCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings
    @Published var extensionEnabled: Bool = true // 先假定已启用，避免闪现横幅

    private let store = ConfigStore()
    private static let extensionBundleId = "com.luyantao.easycontext.finder"

    init() {
        var s = store.load()
        // 启动即 reconcile：并入已安装的内置 App、去重、排序，保留用户选择与自定义项。
        s.reconcile(installedTerminals: Self.installed(KnownApps.terminals),
                    installedEditors: Self.installed(KnownApps.editors))
        self.settings = s
        try? store.save(s)

        refreshExtensionState()
        // App 重新激活时复查（用户去系统设置启用后切回来即更新横幅）。
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshExtensionState() }
        }
    }

    var configPath: String { store.path }

    /// 用 pluginkit 检测扩展是否已启用（宿主非沙盒，可直接跑）。
    func refreshExtensionState() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", Self.extensionBundleId]
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { extensionEnabled = true; return }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 行首 '+' = 启用，'-' = 已注册未启用，空 = 未注册
        extensionEnabled = out.hasPrefix("+")
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// 该 App 是否声明可“打开目录”（用 LaunchServices 查能打开文件夹的 App 列表）。
    func appSupportsOpeningFolder(_ appURL: URL) -> Bool {
        let folder = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let openers = NSWorkspace.shared.urlsForApplications(toOpen: folder)
        return openers.contains { $0.standardizedFileURL == appURL.standardizedFileURL }
    }

    func entries(_ category: AppCategory) -> [AppEntry] {
        category == .terminal ? settings.terminals : settings.editors
    }

    func isInstalled(_ entry: AppEntry) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleId) != nil
    }

    func icon(_ entry: AppEntry) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleId)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func setEnabled(_ entry: AppEntry, on: Bool, category: AppCategory) {
        mutate(category) { list in
            if let i = list.firstIndex(where: { $0.bundleId == entry.bundleId }) {
                list[i].enabled = on
            }
        }
    }

    func removeCustom(_ entry: AppEntry, category: AppCategory) {
        mutate(category) { $0.removeAll { $0.bundleId == entry.bundleId } }
    }

    /// 从 .app 读 bundleId + 名称，作为自定义项追加（已存在则忽略），随后 reconcile 重排。
    func addCustomApp(at url: URL, category: AppCategory) {
        guard let bundleId = Bundle(url: url)?.bundleIdentifier else { return }
        let name = url.deletingPathExtension().lastPathComponent
        let entry = AppEntry(bundleId: bundleId, name: name, custom: true, enabled: true)
        switch category {
        case .terminal:
            if !settings.terminals.contains(where: { $0.bundleId == bundleId }) {
                settings.terminals.append(entry)
            }
        case .editor:
            if !settings.editors.contains(where: { $0.bundleId == bundleId }) {
                settings.editors.append(entry)
            }
        }
        settings.reconcile(installedTerminals: Self.installed(KnownApps.terminals),
                           installedEditors: Self.installed(KnownApps.editors))
        persist()
    }

    func persist() { try? store.save(settings) }

    private func mutate(_ category: AppCategory, _ block: (inout [AppEntry]) -> Void) {
        switch category {
        case .terminal: block(&settings.terminals)
        case .editor: block(&settings.editors)
        }
        persist()
    }

    private static func installed(_ apps: [KnownApp]) -> [KnownApp] {
        AppDetector(isInstalled: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }).installed(from: apps)
    }
}

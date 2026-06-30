import Cocoa
import FinderSync
import EasyContextCore

class FinderSyncExtension: FIFinderSync {
    private let configStore = ConfigStore()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - 目标 URL

    private func targetURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        if let items = controller.selectedItemURLs(), !items.isEmpty {
            return items
        }
        if let target = controller.targetedURL() {
            return [target]
        }
        return []
    }

    private func primaryURL() -> URL? { targetURLs().first }

    private func targetDirectory() -> URL? {
        guard let url = primaryURL() else { return nil }
        return TargetDirectoryResolver().directory(for: url)
    }

    // MARK: - 菜单构建

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else { return nil }
        guard primaryURL() != nil else { return nil }

        let settings = configStore.load()
        let menu = NSMenu(title: "")

        if settings.copyFullPathEnabled {
            addItem(to: menu, title: "复制完整路径", action: #selector(copyFullPath(_:)))
        }
        if settings.copyRelativePathEnabled {
            addItem(to: menu, title: "复制相对路径", action: #selector(copyRelativePath(_:)))
        }

        let detector = AppDetector(isInstalled: Self.isInstalled)
        let terminals = detector.installed(from: KnownApps.terminals)
            .filter { settings.enabledTerminalBundleIds.contains($0.bundleId) }
        let editors = detector.installed(from: KnownApps.editors)
            .filter { settings.enabledEditorBundleIds.contains($0.bundleId) }

        if !terminals.isEmpty || !editors.isEmpty { menu.addItem(.separator()) }
        for app in terminals {
            let item = addItem(to: menu, title: "用 \(app.displayName) 打开终端",
                               action: #selector(openWithApp(_:)))
            item.representedObject = app.bundleId
        }
        for app in editors {
            let item = addItem(to: menu, title: "用 \(app.displayName) 打开",
                               action: #selector(openWithApp(_:)))
            item.representedObject = app.bundleId
        }

        if settings.newFileEnabled {
            menu.addItem(.separator())
            addItem(to: menu, title: "新建文件…", action: #selector(newFile(_:)))
        }
        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    static func isInstalled(_ bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    // MARK: - 动作

    @objc private func copyFullPath(_ sender: AnyObject?) {
        guard let url = primaryURL() else { return }
        writeToPasteboard(url.path)
    }

    @objc private func copyRelativePath(_ sender: AnyObject?) {
        guard let url = primaryURL() else { return }
        writeToPasteboard(RelativePathResolver().relativePath(for: url))
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String,
              let dir = targetDirectory(),
              let app = KnownApps.all.first(where: { $0.bundleId == bundleId })
        else { return }
        run(OpenCommand.open(app: app, directory: dir))
    }

    @objc private func newFile(_ sender: AnyObject?) {
        NSLog("newFile pending")
    }

    private func writeToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private func run(_ spec: ProcessSpec) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.launchPath)
        process.arguments = spec.arguments
        do { try process.run() }
        catch { NSLog("EasyContext open failed: \(error)") }
    }
}

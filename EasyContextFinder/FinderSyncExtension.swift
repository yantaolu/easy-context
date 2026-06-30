import Cocoa
import FinderSync
import EasyContextCore

class FinderSyncExtension: FIFinderSync {
    // FinderSync 的 XPC 往返会丢弃 NSMenuItem.representedObject，
    // 故用 tag 索引这份列表来定位被点的 App。
    private var openableApps: [KnownApp] = []

    override init() {
        super.init()
        updateMonitoredDirectories()
        // 卷挂载/卸载/改名时刷新监控，使外置磁盘即插即生效。
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didMountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didUnmountNotification, object: nil)
        nc.addObserver(self, selector: #selector(volumesChanged),
                       name: NSWorkspace.didRenameVolumeNotification, object: nil)
    }

    @objc private func volumesChanged(_ note: Notification) {
        updateMonitoredDirectories()
    }

    // 监控启动卷 + 所有已挂载卷（单个 "/" 不覆盖 /Volumes/* 外置盘）。
    private func updateMonitoredDirectories() {
        var urls: Set<URL> = [URL(fileURLWithPath: "/")]
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) {
            urls.formUnion(volumes)
        }
        FIFinderSyncController.default().directoryURLs = urls
    }

    // MARK: - 目标 URL

    private func targetURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        if let items = controller.selectedItemURLs(), !items.isEmpty { return items }
        if let target = controller.targetedURL() { return [target] }
        return []
    }

    private func primaryURL() -> URL? { targetURLs().first }

    private func targetDirectory() -> URL? {
        guard let url = primaryURL() else { return nil }
        return TargetDirectoryResolver().directory(for: url)
    }

    // MARK: - 菜单构建
    //
    // v1：扩展自检测并列出所有已装终端/编辑器（沙盒下读不到宿主配置）。

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else { return nil }
        guard primaryURL() != nil else { return nil }

        let menu = NSMenu(title: "")
        addItem(to: menu, title: "复制完整路径", action: #selector(copyFullPath(_:)),
                image: symbolImage("doc.on.doc"))
        addItem(to: menu, title: "复制相对路径", action: #selector(copyRelativePath(_:)),
                image: symbolImage("doc.on.clipboard"))

        let detector = AppDetector(isInstalled: Self.isInstalled)
        let terminals = detector.installed(from: KnownApps.terminals)
        let editors = detector.installed(from: KnownApps.editors)
        openableApps = terminals + editors

        for (idx, app) in terminals.enumerated() {
            let item = addItem(to: menu, title: "用 \(app.displayName) 打开终端",
                               action: #selector(openWithApp(_:)),
                               image: appIcon(forBundleId: app.bundleId) ?? symbolImage("terminal"))
            item.tag = idx
        }
        for (offset, app) in editors.enumerated() {
            let item = addItem(to: menu, title: "用 \(app.displayName) 打开",
                               action: #selector(openWithApp(_:)),
                               image: appIcon(forBundleId: app.bundleId)
                                   ?? symbolImage("chevron.left.forwardslash.chevron.right"))
            item.tag = terminals.count + offset
        }

        // 沙盒扩展不能弹模态窗，新建文件用子菜单选模板、直接创建。
        let newFileItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        newFileItem.image = symbolImage("doc.badge.plus")
        let submenu = NSMenu(title: "新建文件")
        for (idx, template) in FileTemplate.allCases.enumerated() {
            let it = NSMenuItem(title: template.displayName,
                                action: #selector(newFileFromTemplate(_:)), keyEquivalent: "")
            it.target = self
            it.tag = idx
            it.image = symbolImage(Self.templateSymbol(template))
            submenu.addItem(it)
        }
        newFileItem.submenu = submenu
        menu.addItem(newFileItem)
        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector,
                         image: NSImage? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = image
        menu.addItem(item)
        return item
    }

    // MARK: - 图标

    private func symbolImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func appIcon(forBundleId bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private static func templateSymbol(_ t: FileTemplate) -> String {
        switch t {
        case .blank: return "doc"
        case .markdown: return "doc.richtext"
        case .text: return "doc.plaintext"
        case .shell: return "terminal"
        case .json: return "curlybraces"
        }
    }

    private static func isInstalled(_ bundleId: String) -> Bool {
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

    @objc private func openWithApp(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem,
              item.tag >= 0, item.tag < openableApps.count,
              let dir = targetDirectory(),
              let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: openableApps[item.tag].bundleId)
        else { return }
        // 沙盒下不能 spawn /usr/bin/open，改用 LaunchServices。
        NSWorkspace.shared.open([dir], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration(),
                                completionHandler: nil)
    }

    @objc private func newFileFromTemplate(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem,
              item.tag >= 0, item.tag < FileTemplate.allCases.count,
              let dir = targetDirectory() else { return }
        _ = NewFileController.create(template: FileTemplate.allCases[item.tag], in: dir)
    }

    private func writeToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

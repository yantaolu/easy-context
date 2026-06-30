import Cocoa
import CoreImage
import FinderSync
import EasyContextCore

class FinderSyncExtension: FIFinderSync {
    // FinderSync 的 XPC 往返会丢弃 NSMenuItem.representedObject，
    // 故用 tag 索引这份列表来定位被点的 App。
    private var openableApps: [AppEntry] = []

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
    // 扩展按共享配置 config.json 决定显示哪些项 / 哪些 App / 图标风格。

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else { return nil }
        guard primaryURL() != nil else { return nil }

        let config = ConfigStore().load()
        let iconStyle = config.appearance.appIconStyle
        let dark = Self.isDarkMode()
        let menu = NSMenu(title: "")

        if config.items.copyFullPath {
            addItem(to: menu, title: "复制完整路径", action: #selector(copyFullPath(_:)),
                    image: symbolImage("doc.on.doc", dark: dark))
        }
        if config.items.copyRelativePath {
            addItem(to: menu, title: "复制相对路径", action: #selector(copyRelativePath(_:)),
                    image: symbolImage("doc.on.clipboard", dark: dark))
        }

        let terminals = appsToShow(config.terminals, builtins: KnownApps.terminals)
        let editors = appsToShow(config.editors, builtins: KnownApps.editors)
        openableApps = terminals + editors

        for (idx, app) in terminals.enumerated() {
            let item = addItem(to: menu, title: "用 \(app.name) 打开终端",
                               action: #selector(openWithApp(_:)),
                               image: appIcon(app.bundleId, style: iconStyle) ?? symbolImage("terminal", dark: dark))
            item.tag = idx
        }
        for (offset, app) in editors.enumerated() {
            let item = addItem(to: menu, title: "用 \(app.name) 打开",
                               action: #selector(openWithApp(_:)),
                               image: appIcon(app.bundleId, style: iconStyle)
                                   ?? symbolImage("chevron.left.forwardslash.chevron.right", dark: dark))
            item.tag = terminals.count + offset
        }

        guard config.items.newFile else { return menu }
        // 沙盒扩展不能弹模态窗，新建文件用子菜单选模板、直接创建。
        let newFileItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
        newFileItem.image = symbolImage("doc.badge.plus", dark: dark)
        let submenu = NSMenu(title: "新建文件")
        for (idx, template) in FileTemplate.allCases.enumerated() {
            let it = NSMenuItem(title: template.displayName,
                                action: #selector(newFileFromTemplate(_:)), keyEquivalent: "")
            it.target = self
            it.tag = idx
            it.image = symbolImage(Self.templateSymbol(template), dark: dark)
            submenu.addItem(it)
        }
        newFileItem.submenu = submenu
        menu.addItem(newFileItem)
        return menu
    }

    // 要在菜单显示的 App：按配置列表过滤启用且已安装的；列表为空（配置未初始化）
    // 时安全回退到检测到的内置 App。
    private func appsToShow(_ list: [AppEntry], builtins: [KnownApp]) -> [AppEntry] {
        if list.isEmpty {
            let detector = AppDetector(isInstalled: Self.isInstalled)
            return detector.installed(from: builtins)
                .map { AppEntry(bundleId: $0.bundleId, name: $0.displayName) }
        }
        return list.filter { $0.enabled && Self.isInstalled($0.bundleId) }
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

    // FinderSync 会把 template 符号栅格化成固定黑色、不随深浅色变化，
    // 故手动按当前外观给符号着色。
    private func symbolImage(_ name: String, dark: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        else { return nil }
        let color: NSColor = dark ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.15, alpha: 1)
        return Self.tinted(base, color: color)
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let size = image.size
        let out = NSImage(size: size)
        out.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: size),
                   operation: .sourceOver, fraction: 1.0)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    private static let iconSize = NSSize(width: 16, height: 16)

    // SF Symbols（复制/新建/模板）本就是 template 图像，自动适配深浅色，无需处理。
    private static func isDarkMode() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func appIcon(_ bundleId: String, style: Settings.AppIconStyle) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = Self.iconSize
        switch style {
        case .color: return icon
        case .monochrome: return Self.desaturated(icon) ?? icon
        }
    }

    // 纯灰度：保留轮廓细节，浅色/深色下都能看清（中间调在两种背景上都可辨）。
    private static func desaturated(_ image: NSImage) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let source = CIImage(data: tiff) else { return nil }
        let mono = source.applyingFilter("CIPhotoEffectMono")
        let rep = NSCIImageRep(ciImage: mono)
        let result = NSImage(size: iconSize)
        result.addRepresentation(rep)
        result.size = iconSize
        return result
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

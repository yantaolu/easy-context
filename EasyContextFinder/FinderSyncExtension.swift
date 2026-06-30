import Cocoa
import CoreImage
import FinderSync
import EasyContextCore

class FinderSyncExtension: FIFinderSync {
    // FinderSync 的 XPC 往返会丢弃 NSMenuItem.representedObject，
    // 故用 tag 索引这份列表来定位被点的 App。
    private var openableApps: [AppEntry] = []

    // 缓存（扩展进程常驻，跨多次右键存活，避免每次重读/重查/重渲染）。
    private let configStore = ConfigStore()
    private var settingsCache: Settings?
    private var settingsMTime: Date?
    private var urlCache: [String: URL] = [:]       // bundleId -> App URL（只缓存已安装）
    private var imageCache: [String: NSImage] = [:] // "app:bid|style" / "sym:name|dark"

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

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func volumesChanged(_ note: Notification) {
        assert(Thread.isMainThread) // 缓存非线程安全：menu(for:) 与本回调均须在主线程
        updateMonitoredDirectories()
        // 卷增减常伴随 App 增删，清空 App URL / 图标缓存以反映变化。
        urlCache.removeAll()
        imageCache.removeAll()
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
        assert(Thread.isMainThread) // 读写缓存须在主线程（FinderSync 在主线程回调）
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else { return nil }
        guard primaryURL() != nil else { return nil }

        let config = currentSettings()
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
            let detector = AppDetector(isInstalled: isInstalled)
            return detector.installed(from: builtins)
                .map { AppEntry(bundleId: $0.bundleId, name: $0.displayName) }
        }
        return list.filter { $0.enabled && isInstalled($0.bundleId) }
    }

    // 配置按修改时间缓存：mtime 没变就用缓存，避免每次右键重读+解码；
    // 改了 config.json（mtime 变化）即时重读，保留实时生效。
    private func currentSettings() -> Settings {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: configStore.path)[.modificationDate]) as? Date
        if let settingsCache, settingsMTime == mtime { return settingsCache }
        let loaded = configStore.load()
        settingsCache = loaded
        settingsMTime = mtime
        return loaded
    }

    // App URL 缓存：只缓存「已安装」的命中结果。未安装不缓存，避免之后装上了
    // 却因缓存了 nil 而一直不显示（未安装查询本身也很快）。
    private func appURL(_ bundleId: String) -> URL? {
        if let cached = urlCache[bundleId] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        if let url { urlCache[bundleId] = url }
        return url
    }

    private func isInstalled(_ bundleId: String) -> Bool { appURL(bundleId) != nil }

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
        let key = "sym:\(name)|\(dark)"
        if let cached = imageCache[key] { return cached }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        else { return nil }
        let color: NSColor = dark ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.15, alpha: 1)
        let img = Self.tinted(base, color: color)
        imageCache[key] = img
        return img
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
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private func appIcon(_ bundleId: String, style: Settings.AppIconStyle) -> NSImage? {
        let key = "app:\(bundleId)|\(style.rawValue)"
        if let cached = imageCache[key] { return cached }
        guard let url = appURL(bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = Self.iconSize
        let result: NSImage
        switch style {
        case .color: result = icon
        case .monochrome: result = Self.desaturated(icon) ?? icon
        }
        imageCache[key] = result
        return result
    }

    // 纯灰度：保留轮廓细节，浅色/深色下都能看清（中间调在两种背景上都可辨）。
    private static func desaturated(_ image: NSImage) -> NSImage? {
        // 先栅格化到 16×16，避免 CIImage 携带 App 图标的高分位图被长期缓存。
        let small = NSImage(size: iconSize)
        small.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: iconSize),
                   from: .zero, operation: .sourceOver, fraction: 1)
        small.unlockFocus()
        guard let tiff = small.tiffRepresentation,
              let source = CIImage(data: tiff) else { return small }
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
              let url = appURL(openableApps[item.tag].bundleId)
        else { return }
        // 沙盒下不能 spawn /usr/bin/open，改用 LaunchServices。
        NSWorkspace.shared.open([dir], withApplicationAt: url,
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

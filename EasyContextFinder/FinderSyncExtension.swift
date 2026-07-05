import Cocoa
import CoreImage
import FinderSync
import EasyContextCore

class FinderSyncExtension: FIFinderSync {
    // FinderSync 的 XPC 往返会丢弃 NSMenuItem.representedObject，
    // 故用 tag 索引这些列表来定位被点的项。
    private var openableApps: [AppEntry] = []
    private var openableTerminalCount = 0 // openableApps 前 N 个是终端，其余是编辑器
    private var runnableCommands: [CommandEntry] = []
    private var commandTerm: String = ""
    // 本次菜单对应的目标 URL 快照（按 menuKind 定，多选时含全部选中项），动作回调
    // 用它、不在点击时重解析，避免「容器右键却命中残留选中项」及构建↔点击间目标漂移。
    private var menuTargetURLs: [URL] = []

    // 缓存（扩展进程常驻，跨多次右键存活，避免每次重读/重查/重渲染）。
    // 注意：menu(for:) 在 XPC 工作线程回调、volumesChanged 在主线程，两者会并发
    // 访问下列缓存，故所有读写都要走 cacheLock（用递归锁以允许 appIcon→appURL 嵌套）。
    private let configStore = ConfigStore()
    private let cacheLock = NSRecursiveLock()
    private var settingsCache: Settings?
    private var settingsMTime: Date?
    private var urlCache: [String: URL] = [:]       // bundleId -> App URL（只缓存已安装）
    private var imageCache: [String: NSImage] = [:] // "app:bid|path|style" / "sym:name|dark"
    private var appSnapshotCache: InstalledAppSnapshot?
    private var appSnapshotBundleIds: Set<String> = []
    private var appSnapshotTime: Date?
    private let appSnapshotTTL: TimeInterval = 1

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
        updateMonitoredDirectories()
        // 卷增减常伴随 App 增删，清空 App URL / 图标缓存以反映变化。
        cacheLock.lock()
        urlCache.removeAll()
        imageCache.removeAll()
        appSnapshotCache = nil
        appSnapshotBundleIds.removeAll()
        appSnapshotTime = nil
        cacheLock.unlock()
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

    // 按 menuKind 定目标：容器菜单（空白处右键）优先容器本身，避免命中残留选中项；
    // 条目菜单取全部选中项（FinderSync 拿不到「鼠标落点是哪一项」；右键点选中集外
    // 的项时 Finder 会自动把选中变成它一个，故这里天然是"点哪对哪"或"整个选中集"）。
    private func resolveTargets(for menuKind: FIMenuKind) -> [URL] {
        let c = FIFinderSyncController.default()
        switch menuKind {
        case .contextualMenuForContainer:
            if let target = c.targetedURL() { return [target] }
            return c.selectedItemURLs() ?? []
        default:
            if let selected = c.selectedItemURLs(), !selected.isEmpty { return selected }
            return c.targetedURL().map { [$0] } ?? []
        }
    }

    // 动作回调读的是构建菜单时定下的快照，而非重新解析当前 Finder 状态。
    private func snapshotURLs() -> [URL] {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return menuTargetURLs
    }

    // 快照对应的目录集合：文件→父目录，去重、保持顺序（普通视图下多选同目录 → 1 个；
    // 搜索结果等跨目录多选才会出现多个）。
    private func targetDirectories() -> [URL] {
        let resolver = TargetDirectoryResolver()
        var seen = Set<String>()
        var dirs: [URL] = []
        for url in snapshotURLs() {
            let dir = resolver.directory(for: url)
            if seen.insert(dir.path).inserted { dirs.append(dir) }
        }
        return dirs
    }

    // MARK: - 菜单构建
    //
    // 扩展按共享配置 config.json 决定显示哪些项 / 哪些 App / 图标风格。

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else { return nil }
        let targets = resolveTargets(for: menuKind)
        guard !targets.isEmpty else { return nil }
        cacheLock.lock(); menuTargetURLs = targets; cacheLock.unlock()

        let config = currentSettings()
        let appSnapshot = currentAppSnapshot(for: config)
        let iconStyle = config.appearance.appIconStyle
        let dark = Self.isDarkMode()
        let menu = NSMenu(title: "")

        if config.items.copyFullPath {
            addItem(to: menu, title: String(localized: "Copy Path"), action: #selector(copyFullPath(_:)),
                    image: symbolImage("doc.on.doc", dark: dark))
        }
        if config.items.copyRelativePath {
            addItem(to: menu, title: String(localized: "Copy Relative Path"), action: #selector(copyRelativePath(_:)),
                    image: symbolImage("doc.on.clipboard", dark: dark))
        }

        let terminals = appsToShow(config.terminals, builtins: KnownApps.terminals, snapshot: appSnapshot)
        let editors = appsToShow(config.editors, builtins: KnownApps.editors, snapshot: appSnapshot)
        cacheLock.lock()
        openableApps = terminals + editors
        openableTerminalCount = terminals.count
        cacheLock.unlock()

        for (idx, app) in terminals.enumerated() {
            let item = addItem(to: menu, title: String(localized: "Open Terminal with \(app.name)"),
                               action: #selector(openWithApp(_:)),
                               image: appIcon(app.bundleId, style: iconStyle, snapshot: appSnapshot) ?? symbolImage("terminal", dark: dark))
            item.tag = idx
        }
        for (offset, app) in editors.enumerated() {
            let item = addItem(to: menu, title: String(localized: "Open with \(app.name)"),
                               action: #selector(openWithApp(_:)),
                               image: appIcon(app.bundleId, style: iconStyle, snapshot: appSnapshot)
                                   ?? symbolImage("chevron.left.forwardslash.chevron.right", dark: dark))
            item.tag = terminals.count + offset
        }

        // 在执行终端运行命令（claude/codex 等）。执行终端与「菜单是否显示」解耦，
        // 只要装了就能用；故从「已安装终端」解析（忽略启用状态），再过滤出有启动
        // 模板的（与宿主 SettingsStore.installedTerminals 同口径）——无模板的终端
        // 被解析为执行终端后点击必然失败。
        let enabledCmds = config.commands.filter { $0.enabled }
        if !enabledCmds.isEmpty {
            let installedTerms = TerminalLaunch.launchable(
                installedTerminals(config.terminals, snapshot: appSnapshot),
                overrides: config.terminalTemplates)
            let termId = TerminalLaunch.resolveDefaultTerminal(eligible: installedTerms,
                                                              preferred: config.defaultTerminal)
            let termName = terminalName(termId, eligible: installedTerms)
            cacheLock.lock()
            runnableCommands = enabledCmds
            commandTerm = termId
            cacheLock.unlock()
            let termIcon = appIcon(termId, style: iconStyle, snapshot: appSnapshot) ?? symbolImage("terminal", dark: dark)
            for (idx, cmd) in enabledCmds.enumerated() {
                let item = addItem(to: menu, title: String(localized: "Run \(cmd.name) in \(termName)"),
                                   action: #selector(openWithCommand(_:)), image: termIcon)
                item.tag = idx
            }
        }

        guard config.items.newFile else { return menu }
        // 沙盒扩展不能弹模态窗：新建文件用子菜单选模板，点选后交宿主弹命名面板创建。
        let newFileItem = NSMenuItem(title: String(localized: "New File"), action: nil, keyEquivalent: "")
        newFileItem.image = symbolImage("doc.badge.plus", dark: dark)
        let submenu = NSMenu(title: String(localized: "New File"))
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
    private func appsToShow(_ list: [AppEntry], builtins: [KnownApp],
                            snapshot: InstalledAppSnapshot) -> [AppEntry] {
        if list.isEmpty {
            return snapshot.knownApps(from: builtins)
                .map { AppEntry(bundleId: $0.bundleId, name: $0.displayName) }
        }
        return list
            .filter { $0.enabled && snapshot.isInstalled($0.bundleId) }
            .map { snapshot.refreshedEntry($0) }
    }

    // 已安装的终端（忽略「菜单显示」开关）；配置为空时回退到检测到的内置终端。
    private func installedTerminals(_ list: [AppEntry], snapshot: InstalledAppSnapshot) -> [AppEntry] {
        if list.isEmpty {
            return snapshot.knownApps(from: KnownApps.terminals)
                .map { AppEntry(bundleId: $0.bundleId, name: $0.displayName) }
        }
        return list
            .filter { snapshot.isInstalled($0.bundleId) }
            .map { snapshot.refreshedEntry($0) }
    }

    private func terminalName(_ bundleId: String, eligible: [AppEntry]) -> String {
        if let e = eligible.first(where: { $0.bundleId == bundleId }) { return e.name }
        if let k = KnownApps.terminals.first(where: { $0.bundleId == bundleId }) { return k.displayName }
        return bundleId
    }

    private func probeBundleIds(_ config: Settings) -> Set<String> {
        var ids = Set<String>()
        if config.terminals.isEmpty {
            ids.formUnion(KnownApps.terminals.map(\.bundleId))
        } else {
            ids.formUnion(config.terminals.map(\.bundleId))
        }
        if config.editors.isEmpty {
            ids.formUnion(KnownApps.editors.map(\.bundleId))
        } else {
            ids.formUnion(config.editors.filter(\.enabled).map(\.bundleId))
        }
        if let defaultTerminal = config.defaultTerminal { ids.insert(defaultTerminal) }
        return ids
    }

    private func currentAppSnapshot(for config: Settings) -> InstalledAppSnapshot {
        let bundleIds = probeBundleIds(config)
        let now = Date()
        cacheLock.lock()
        if let appSnapshotCache, appSnapshotBundleIds == bundleIds,
           let appSnapshotTime, now.timeIntervalSince(appSnapshotTime) < appSnapshotTTL {
            defer { cacheLock.unlock() }
            return appSnapshotCache
        }
        cacheLock.unlock()

        let snapshot = InstalledAppSnapshot.capture(bundleIds: bundleIds)
        cacheLock.lock()
        appSnapshotCache = snapshot
        appSnapshotBundleIds = bundleIds
        appSnapshotTime = now
        cacheLock.unlock()
        return snapshot
    }

    // 配置按修改时间缓存：mtime 没变就用缓存，避免每次右键重读+解码；
    // 改了 config.json（mtime 变化）即时重读，保留实时生效。
    private func currentSettings() -> Settings {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: configStore.path)[.modificationDate]) as? Date
        cacheLock.lock()
        if let settingsCache, settingsMTime == mtime { defer { cacheLock.unlock() }; return settingsCache }
        cacheLock.unlock()
        var loaded = configStore.load() // 读盘+解码在锁外，避免阻塞主线程的 volumesChanged
        loaded.normalizeCommandNames(defaultName: String(localized: "Command"))
        cacheLock.lock()
        settingsCache = loaded
        settingsMTime = mtime
        cacheLock.unlock()
        return loaded
    }

    // App URL 缓存：只缓存「已安装」的命中结果。未安装不缓存，避免之后装上了
    // 却因缓存了 nil 而一直不显示（未安装查询本身也很快）。
    private func appURL(_ bundleId: String) -> URL? {
        cacheLock.lock()
        if let cached = urlCache[bundleId] {
            if FileManager.default.fileExists(atPath: cached.path) {
                defer { cacheLock.unlock() }
                return cached
            }
            urlCache.removeValue(forKey: bundleId)
        }
        cacheLock.unlock()
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) // 锁外
        if let url {
            cacheLock.lock(); urlCache[bundleId] = url; cacheLock.unlock()
        }
        return url
    }

    private func freshAppURL(_ bundleId: String) -> URL? {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        cacheLock.lock()
        if let url {
            urlCache[bundleId] = url
        } else {
            urlCache.removeValue(forKey: bundleId)
            imageCache = imageCache.filter { !$0.key.hasPrefix("app:\(bundleId)|") }
            appSnapshotCache = nil
            appSnapshotBundleIds.removeAll()
            appSnapshotTime = nil
        }
        cacheLock.unlock()
        return url
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
        let key = "sym:\(name)|\(dark)"
        cacheLock.lock()
        if let cached = imageCache[key] { defer { cacheLock.unlock() }; return cached }
        cacheLock.unlock()
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        else { return nil }
        let color: NSColor = dark ? NSColor(white: 0.90, alpha: 1) : NSColor(white: 0.15, alpha: 1)
        let img = Self.tinted(base, color: color) // 渲染在锁外
        cacheLock.lock(); imageCache[key] = img; cacheLock.unlock()
        return img
    }

    // 线程安全的离屏渲染：用 bitmap-backed NSGraphicsContext（thread-local），
    // 不用 NSImage.lockFocus（那是主线程取向的 API，工作线程上属未受支持路径）。
    private static func offscreen(size: NSSize, scale: CGFloat = 2,
                                  _ draw: (NSRect) -> Void) -> NSImage? {
        let pxW = Int((size.width * scale).rounded()), pxH = Int((size.height * scale).rounded())
        guard pxW > 0, pxH > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = size
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }

    private static func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        offscreen(size: image.size) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            color.set()
            rect.fill(using: .sourceAtop)
        } ?? image
    }

    private static let iconSize = NSSize(width: 16, height: 16)

    // 系统外观（深浅色）：手动模式读全局 AppleInterfaceStyle（线程安全）；
    // 「自动切换」模式下该键不跟随时段翻转、不可靠 → 改问 AppKit 的 effectiveAppearance
    // （主线程属性，工作线程经 main.sync 跳转读取）。
    // ⚠️ 勿在持有 cacheLock 时调用：main.sync 与主线程等锁（volumesChanged）会成死锁环。
    private static func isDarkMode() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically") {
            let resolve = {
                NSApplication.shared.effectiveAppearance
                    .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            }
            return Thread.isMainThread ? resolve() : DispatchQueue.main.sync(execute: resolve)
        }
        return defaults.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    private func appIcon(_ bundleId: String, style: Settings.AppIconStyle,
                         snapshot: InstalledAppSnapshot? = nil) -> NSImage? {
        guard let url = snapshot?.info(for: bundleId)?.url ?? appURL(bundleId) else { return nil }   // appURL 自带锁，此处不嵌套
        let key = "app:\(bundleId)|\(url.path)|\(style.rawValue)"
        cacheLock.lock()
        if let cached = imageCache[key] { defer { cacheLock.unlock() }; return cached }
        cacheLock.unlock()
        let icon = NSWorkspace.shared.icon(forFile: url.path)  // 取图标 + 渲染都在锁外
        icon.size = Self.iconSize
        let result: NSImage
        switch style {
        case .color: result = icon
        case .monochrome: result = Self.desaturated(icon) ?? icon
        }
        cacheLock.lock(); imageCache[key] = result; cacheLock.unlock()
        return result
    }

    private static let ciContext = CIContext()

    // 纯灰度：保留轮廓细节，浅色/深色下都能看清（中间调在两种背景上都可辨）。
    private static func desaturated(_ image: NSImage) -> NSImage? {
        // 先用线程安全离屏栅格化到 16×16，避免缓存高分位图。
        guard let small = offscreen(size: iconSize, { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }), let tiff = small.tiffRepresentation, let source = CIImage(data: tiff) else { return nil }
        let mono = source.applyingFilter("CIPhotoEffectMono")
        // 用 CIContext 渲染成实体 CGImage，避免 NSCIImageRep 的延迟渲染。
        guard let cg = ciContext.createCGImage(mono, from: mono.extent) else { return small }
        return NSImage(cgImage: cg, size: iconSize)
    }

    private static func templateSymbol(_ t: FileTemplate) -> String {
        switch t {
        case .markdown: return "doc.richtext"
        case .text: return "doc.plaintext"
        case .shell: return "terminal"
        case .json: return "curlybraces"
        }
    }

    // MARK: - 动作

    @objc private func copyFullPath(_ sender: AnyObject?) {
        let urls = snapshotURLs()
        guard !urls.isEmpty else { return }
        writeToPasteboard(urls.map(\.path).joined(separator: "\n"))
    }

    @objc private func copyRelativePath(_ sender: AnyObject?) {
        let urls = snapshotURLs()
        guard !urls.isEmpty else { return }
        let resolver = RelativePathResolver()
        writeToPasteboard(urls.map { resolver.relativePath(for: $0) }.joined(separator: "\n"))
    }

    @objc private func openWithApp(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem else { return }
        cacheLock.lock()
        let apps = openableApps
        let terminalCount = openableTerminalCount
        cacheLock.unlock()
        guard item.tag >= 0, item.tag < apps.count,
              let url = freshAppURL(apps[item.tag].bundleId)
        else { return }
        // 终端只能对目录（文件→父目录，多选去重）；编辑器打开右键对象本身（多选全开）。
        let isTerminal = item.tag < terminalCount
        let targets = isTerminal ? targetDirectories() : snapshotURLs()
        guard !targets.isEmpty else { return }
        // 沙盒下不能 spawn /usr/bin/open，改用 LaunchServices。
        NSWorkspace.shared.open(targets, withApplicationAt: url,
                                configuration: NSWorkspace.OpenConfiguration(),
                                completionHandler: nil)
    }

    // 在默认终端运行命令：构造 easycontext:// URL 交给宿主执行（沙盒不能自己 spawn）。
    @objc private func openWithCommand(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem else { return }
        cacheLock.lock()
        let cmds = runnableCommands
        let term = commandTerm
        cacheLock.unlock()
        guard item.tag >= 0, item.tag < cmds.count, !term.isEmpty,
              let dir = targetDirectories().first else { return }
        var comps = URLComponents()
        comps.scheme = "easycontext"
        comps.host = "run"
        comps.queryItems = [
            URLQueryItem(name: "cmd", value: cmds[item.tag].name),
            URLQueryItem(name: "dir", value: dir.path),
            URLQueryItem(name: "term", value: term),
            // ensure：token 缺失（宿主从未运行/被清理）时由扩展补建，避免首次点击静默失败。
            URLQueryItem(name: "t", value: ConfigStore().ensureIPCToken()), // 宿主据此验真
        ]
        guard let url = comps.url else { return }
        NSWorkspace.shared.open(url)
    }

    // 新建文件：交给宿主弹命名面板→创建→在 Finder 选中（沙盒扩展不能弹 UI）。
    @objc private func newFileFromTemplate(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem,
              item.tag >= 0, item.tag < FileTemplate.allCases.count,
              let dir = targetDirectories().first else { return }
        var comps = URLComponents()
        comps.scheme = "easycontext"
        comps.host = "newfile"
        comps.queryItems = [
            URLQueryItem(name: "dir", value: dir.path),
            URLQueryItem(name: "template", value: FileTemplate.allCases[item.tag].rawValue),
            URLQueryItem(name: "t", value: ConfigStore().ensureIPCToken()),
        ]
        guard let url = comps.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func writeToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

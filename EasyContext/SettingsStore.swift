import Foundation
import AppKit
import FinderSync
import EasyContextCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings
    @Published var extensionEnabled: Bool = true // 先假定已启用，避免闪现横幅
    @Published var configCorrupt: Bool = false    // 配置损坏（已备份、用默认）→ 顶部横幅提示
    @Published var saveFailed: Bool = false       // persist() 写盘失败 → 顶部横幅提示

    private let store = ConfigStore()
    private static let extensionBundleId = "com.luyantao.easycontext.finder"
    private var activeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var lastToken: ConfigStore.FileToken?       // 上次读/写时的 config.json 指纹（识别外部改动）
    private var lastInstallSignature: Set<String> = []  // 上次的已安装条目集合（识别条目装/卸）
    // 首轮探测在后台跑，就绪前为 nil → isInstalled 乐观视为已安装（配置里的条目
    // 绝大多数确实装着），列表立即可见、快照就绪后校正——避免首窗卡顿或闪空。
    private var installedSnapshot: InstalledAppSnapshot?
    private var iconCache: [String: NSImage] = [:]
    private static var defaultCommandName: String { String(localized: "Command") }

    init() {
        // 区分「缺失」与「损坏」：损坏时备份原文件、用默认、且【不自动覆盖】原文件。
        let outcome = store.loadOutcome()
        let original: Settings
        switch outcome {
        case .ok(let loaded): original = loaded
        case .missing: original = Settings()
        case .corrupt:
            configCorrupt = true
            store.backupCorruptFile()
            original = Settings()
        }
        var s = original
        s.normalizeCommands(defaultName: Self.defaultCommandName)
        self.settings = s
        // 内容没变就不重写，避免无谓 bump mtime（否则扩展端缓存会被迫重载一次）。
        // 损坏时【不写】——避免默认值覆盖用户可修复的原文件（已备份到 .bak）。
        // 首次写盘失败同样亮 saveFailed 横幅（与后续 persist 失败同口径）。
        if outcome != .corrupt, s != original || !store.hasStored() {
            if (try? store.save(s)) == nil { saveFailed = true }
        }
        // 记录基线：文件指纹用于识别 config.json 的外部改动，安装签名用于识别条目装/卸。
        lastToken = store.fileToken()
        // 注：IPC token 生成与模板参考文件写出已移到 AppDelegate（无论是否显示设置窗都要跑）。

        refreshExtensionState()
        // 宿主常驻后台、窗口/StateObject 只建一次：App 重新激活时统一刷新——
        // refreshExtensionState 只管扩展启用横幅；refreshAppList 让列表与「磁盘配置 + 实时安装态」一致。
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshExtensionState()
                await self?.refreshAppList()
            }
        }
        // ⌘Q 兜底：命令编辑只在失焦/回车落盘，改完直接退出会丢——willTerminate 时
        // flush。此后没有 runloop，须同步执行（通知在主线程送达，assumeIsolated 成立）。
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushCommands() }
        }
        // 首轮安装态探测 + reconcile（几十次 LaunchServices 查询）放后台，避免首窗卡顿。
        Task { await self.refreshAppList() }
    }

    deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    var configPath: String { store.path }

    /// 用 pluginkit 检测扩展是否已启用（宿主非沙盒，可直接跑）。
    /// 放到后台执行——避免在主线程同步等子进程退出造成启动/切前台卡顿。
    func refreshExtensionState() {
        let bundleId = Self.extensionBundleId
        Task.detached(priority: .utility) { [weak self] in
            let enabled = SettingsStore.queryExtensionEnabled(bundleId)
            await MainActor.run { [weak self] in self?.extensionEnabled = enabled }
        }
    }

    nonisolated private static func queryExtensionEnabled(_ bundleId: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-i", bundleId]
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch { return true }
        // 5s 超时兜底：pluginkit 挂死时终止之，避免后台任务永久等待。
        let killTimer = DispatchWorkItem { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: killTimer)
        // 先读完管道再等退出，避免输出超管道缓冲时的死锁形态。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killTimer.cancel()
        // 被超时终止 → 状态未知，乐观视为已启用（与 run 失败同口径，避免误吓用户）。
        if process.terminationReason == .uncaughtSignal { return true }
        let out = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 行首 '+' = 启用，'-' = 已注册未启用，空 = 未注册。
        // 同一 bundleId 可能注册多行（如 build 目录与 /Applications 各一份，顺序不定），
        // 任一行启用即视为启用——只看首行会误报「未启用」横幅。
        return out.split(separator: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("+")
        }
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

    /// 统一刷新：让显示列表与「磁盘 config.json + 实时安装态」保持一致。init 与 App
    /// 重新激活时调用。三步、幂等——无变化则不写盘、不重渲染：
    ///   ① reloadIfChanged：外部改过配置就重读覆盖内存；
    ///   ② reconcile：并入运行期新装的内置 App（轴 A，条目集变化）；
    ///   ③ 安装签名：已有条目装/卸时强制重渲染，让 visibleEntries 的实时 isInstalled 重算（轴 B）。
    func refreshAppList() async {
        var published = reloadIfChanged()

        // 一次安装态快照，放离主线程——避免切前台时在主线程同步等 40+ 次 LaunchServices 查询
        // （与 refreshExtensionState 的后台化约定一致）。probe 须在挂起前于主线程取值。
        let probe = probeBundleIds
        let snapshot = await Task.detached { InstalledAppSnapshot.capture(bundleIds: probe) }.value
        installedSnapshot = snapshot

        iconCache.removeAll() // 快照更新 → App 可能装/卸/搬家，图标缓存作废

        var s = settings
        s.reconcile(installedTerminals: snapshot.knownApps(from: KnownApps.terminals),
                    installedEditors:   snapshot.knownApps(from: KnownApps.editors))
        s.refreshInstalledNames(using: snapshot)
        if s != settings {
            settings = s                       // @Published → 重渲染
            // 损坏时只更新内存，不覆盖用户那份已备份、可手动修复的原文件（与 init 一致）。
            if !configCorrupt { persist() }
            published = true
        }

        // 轴 B：条目安装态翻转 → 仅在真的变了、且本次尚未因 settings 变更而重渲染时，手动触发。
        // 注：probe 在挂起前取值，若这期间用户恰好新增自定义 App，其安装态本轮未探到、会被当
        // 未安装暂不显示，下次激活自愈——概率极低，可接受。
        let sig = signature(snapshot: snapshot)
        if sig != lastInstallSignature {
            lastInstallSignature = sig
            if !published { objectWillChange.send() }
        }
    }

    /// config.json 被外部改过（用户手改 / 扩展端写盘）就重读覆盖内存，返回是否产生可观察变更。
    /// 防自写回环：宿主自己 persist 后会补记 lastToken，故不会把自身写盘误判为外部改动。
    private func reloadIfChanged() -> Bool {
        let token = store.fileToken()
        guard token != lastToken else { return false }
        lastToken = token   // 即使损坏/缺失也更新——避免每次激活重复备份；用户再改时 token 会再变。

        switch store.loadOutcome() {
        case .ok(let rawLoaded):
            var loaded = rawLoaded
            loaded.normalizeCommands(defaultName: Self.defaultCommandName)
            var published = false
            if settings != loaded {
                settings = loaded
                published = true
            }
            if configCorrupt { configCorrupt = false; published = true }  // 用户把文件修好了 → 撤横幅
            if loaded != rawLoaded { persist() }
            return published
        case .corrupt:
            store.backupCorruptFile()
            guard !configCorrupt else { return false }
            configCorrupt = true
            return true
        case .missing:
            // 文件被删：保留当前内存（不清空成默认），下次任一 persist 自动重建。
            return false
        }
    }

    /// 需要探测安装态的全部 bundleId：内置名单 ∪ 当前条目（含自定义）。
    private var probeBundleIds: Set<String> {
        Self.probeBundleIds(settings: settings)
    }

    private static func probeBundleIds(settings: Settings) -> Set<String> {
        Set(KnownApps.terminals.map(\.bundleId) + KnownApps.editors.map(\.bundleId)
            + settings.terminals.map(\.bundleId) + settings.editors.map(\.bundleId))
    }

    /// 已安装条目的 bundleId 集合——轴 B 的「安装态签名」，由一次安装态快照派生（不再各自查 LS）。
    private func signature(snapshot: InstalledAppSnapshot) -> Set<String> {
        Set((settings.terminals + settings.editors).map(\.bundleId).filter { snapshot.isInstalled($0) })
    }

    func entries(_ category: AppCategory) -> [AppEntry] {
        category == .terminal ? settings.terminals : settings.editors
    }

    /// 设置界面只展示【已安装】的 App：未安装的仍保留在配置里（保留开关状态、
    /// 重装后自动回来），只是不在列表里显示——避免出现卸载后残留的“未安装”死条目。
    func visibleEntries(_ category: AppCategory) -> [AppEntry] {
        entries(category).filter { isInstalled($0) }
    }

    func isInstalled(_ entry: AppEntry) -> Bool {
        installedSnapshot?.isInstalled(entry.bundleId) ?? true // 快照未就绪 → 乐观已安装
    }

    func icon(_ entry: AppEntry) -> NSImage? {
        guard let info = installedSnapshot?.info(for: entry.bundleId) else { return nil }
        let key = entry.bundleId + "|" + info.url.path
        if let cached = iconCache[key] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: info.url.path)
        iconCache[key] = icon
        return icon
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

    /// 从 .app 读 bundleId + 名称，作为自定义项追加（已存在则忽略）。
    /// 不做同步 LaunchServices 查询：名称直接从所选 .app 读、快照原地并入（刚选中的
    /// App 必然已安装），排序 / custom 标记 / 安装签名交给后台 refreshAppList 统一校正。
    /// 返回是否成功（false = 读不出 bundleId，由 UI 提示）。
    @discardableResult
    func addCustomApp(at url: URL, category: AppCategory) -> Bool {
        guard let bundleId = Bundle(url: url)?.bundleIdentifier else { return false }
        let name = InstalledAppSnapshot.displayName(
            for: url, fallback: url.deletingPathExtension().lastPathComponent)
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
        installedSnapshot = installedSnapshot?.adding(
            InstalledAppInfo(bundleId: bundleId, url: url, displayName: name))
        persist()
        Task { await refreshAppList() }
        return true
    }

    // MARK: - 自定义命令

    func command(_ id: String) -> CommandEntry? {
        settings.commands.first { $0.id == id }
    }

    /// 追加一条新命令（默认启用），起名自动避开已有名字（纯体验，不是强制唯一）。
    /// 结构性改动 → 立即写盘。
    func addCommand() {
        let name = Self.uniqueCommandName(in: settings.commands)
        settings.commands.append(CommandEntry(name: name, command: "", enabled: true))
        persist()
    }

    /// 结构性改动 → 立即写盘。
    func removeCommand(id: String) {
        settings.commands.removeAll { $0.id == id }
        persist()
    }

    // 命令名编辑：先只改内存，失焦/回车时落盘（名字是纯显示文本，无需校验唯一）。
    func updateCommandName(id: String, _ value: String) {
        guard let i = settings.commands.firstIndex(where: { $0.id == id }) else { return }
        settings.commands[i].name = value
    }

    func updateCommandString(id: String, _ value: String) {
        guard let i = settings.commands.firstIndex(where: { $0.id == id }) else { return }
        settings.commands[i].command = value
        scheduleSave()
    }

    /// UI 在输入框失焦/回车时调用，立刻落盘（并取消挂起的防抖任务）。
    /// normalize 只做 trim + 空名补默认名（执行按 id，名字不再强制唯一）。
    func flushCommands() {
        saveTask?.cancel()
        saveTask = nil
        settings.normalizeCommands(defaultName: Self.defaultCommandName)
        persist()
    }

    private var saveTask: Task<Void, Never>?

    /// 防抖写盘：合并连续按键，最后一次后 0.4s 才写盘，避免每字符一次磁盘 I/O。
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.flushCommands()
        }
    }

    // MARK: - 默认终端（运行命令用）

    /// 可用作执行终端的终端（按配置顺序）：已安装且有启动模板（内置或用户覆盖），
    /// 与菜单显示开关无关。无模板的终端（如 Warp/Hyper）不进候选——选了也必然运行失败。
    var installedTerminals: [AppEntry] {
        TerminalLaunch.launchable(allInstalledTerminals, overrides: settings.terminalTemplates)
    }

    /// 全部已安装终端（不做模板过滤）——模板编辑器用，含尚无模板的终端。
    var allInstalledTerminals: [AppEntry] {
        settings.terminals.filter { isInstalled($0) }
    }

    // MARK: - 终端启动模板（编辑器）

    /// 某终端当前生效的模板与来源（覆盖优先于内置）。
    func templateInfo(for bundleId: String) -> (effective: String, isOverridden: Bool, hasBuiltin: Bool) {
        let builtin = TerminalLaunch.builtinTemplates[bundleId]
        let override = settings.terminalTemplates[bundleId]
        return (override ?? builtin ?? "", override != nil, builtin != nil)
    }

    /// 写/清模板覆盖：空串或与内置相同 → 移除覆盖（回到内置/无模板）；否则写入。
    /// 立即落盘——扩展菜单与执行终端候选随之更新。
    func setTemplateOverride(_ template: String, for bundleId: String) {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == TerminalLaunch.builtinTemplates[bundleId] {
            settings.terminalTemplates.removeValue(forKey: bundleId)
        } else {
            settings.terminalTemplates[bundleId] = trimmed
        }
        persist()
    }

    /// 执行终端下拉的选项，永不为空：无已安装终端时回退系统 Terminal，
    /// 保证下拉框始终存在（不再切换成文字提示→避免抖动）。
    var terminalOptions: [AppEntry] {
        let installed = installedTerminals
        if !installed.isEmpty { return installed }
        let sysId = TerminalLaunch.systemTerminalBundleId
        if let sys = settings.terminals.first(where: { $0.bundleId == sysId }) { return [sys] }
        return [AppEntry(bundleId: sysId, name: "Terminal", custom: false, enabled: false)]
    }

    /// 当前生效的执行终端 bundleId（解析后的，nil 偏好回退到第一个已安装）。
    var resolvedDefaultTerminal: String {
        TerminalLaunch.resolveDefaultTerminal(eligible: installedTerminals,
                                              preferred: settings.defaultTerminal)
    }

    func setDefaultTerminal(_ bundleId: String) {
        settings.defaultTerminal = bundleId
        persist()
    }

    func persist() {
        guard (try? store.save(settings)) != nil else {
            // 写盘失败（磁盘满/权限等）：内存保持新状态，横幅提示「仅本次会话生效」。
            if !saveFailed { saveFailed = true }
            return
        }
        if saveFailed { saveFailed = false }
        lastToken = store.fileToken()   // 记住自身写盘的指纹，避免 reloadIfChanged 把它误判为外部改动
        // 损坏状态下用户主动改动会写出一份合法配置 → 撤下损坏横幅（原文件仍留在 .bak）。
        if configCorrupt { configCorrupt = false }
    }

    private func mutate(_ category: AppCategory, _ block: (inout [AppEntry]) -> Void) {
        switch category {
        case .terminal: block(&settings.terminals)
        case .editor: block(&settings.editors)
        }
        persist()
    }

    /// 新命令的默认起名：避开已有名字（Command、Command2…）。纯体验，不是唯一性约束。
    private static func uniqueCommandName(in commands: [CommandEntry]) -> String {
        let used = Set(commands.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
        var name = defaultCommandName
        var n = 1
        while used.contains(name) {
            n += 1
            name = "\(defaultCommandName)\(n)"
        }
        return name
    }
}

private extension Settings {
    mutating func refreshInstalledNames(using snapshot: InstalledAppSnapshot) {
        terminals = terminals.map { snapshot.refreshedEntry($0) }
        editors = editors.map { snapshot.refreshedEntry($0) }
    }
}

import Foundation

/// 列表中的一个 App 条目。
public struct AppEntry: Codable, Equatable, Sendable, Identifiable {
    public var bundleId: String
    public var name: String
    public var custom: Bool     // false=内置清单；true=用户自定义添加
    public var enabled: Bool    // 是否在右键菜单显示

    public var id: String { bundleId }

    public init(bundleId: String, name: String, custom: Bool = false, enabled: Bool = true) {
        self.bundleId = bundleId
        self.name = name
        self.custom = custom
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try c.decode(String.self, forKey: .bundleId)
        name = c.value(.name, default: "")
        custom = c.value(.custom, default: false)
        enabled = c.value(.enabled, default: true)
    }
}

/// 共享配置（宿主 GUI 与 FinderSync 扩展读写同一份 JSON）。
/// 解码对缺失字段容忍——手改文件少写某项时回退默认值。
public struct Settings: Codable, Equatable, Sendable {
    public var version: Int
    public var items: Items
    public var terminals: [AppEntry]
    public var editors: [AppEntry]
    public var commands: [CommandEntry]
    public var defaultTerminal: String?          // 终端 bundleId；nil=按解析逻辑
    public var terminalTemplates: [String: String] // bundleId -> 用户覆盖的启动模板
    public var appearance: Appearance

    public static let defaultCommands: [CommandEntry] = [
        CommandEntry(name: "Claude", command: "claude"),
        CommandEntry(name: "Codex", command: "codex"),
    ]

    public init(
        version: Int = 3,
        items: Items = Items(),
        terminals: [AppEntry] = [],
        editors: [AppEntry] = [],
        commands: [CommandEntry] = Settings.defaultCommands,
        defaultTerminal: String? = nil,
        terminalTemplates: [String: String] = [:],
        appearance: Appearance = Appearance()
    ) {
        self.version = version
        self.items = items
        self.terminals = terminals
        self.editors = editors
        self.commands = commands
        self.defaultTerminal = defaultTerminal
        self.terminalTemplates = terminalTemplates
        self.appearance = appearance
    }

    public struct Items: Codable, Equatable, Sendable {
        public var copyFullPath: Bool
        public var copyRelativePath: Bool
        public var newFile: Bool

        public init(copyFullPath: Bool = true, copyRelativePath: Bool = true, newFile: Bool = true) {
            self.copyFullPath = copyFullPath
            self.copyRelativePath = copyRelativePath
            self.newFile = newFile
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Items()
            copyFullPath = c.value(.copyFullPath, default: d.copyFullPath)
            copyRelativePath = c.value(.copyRelativePath, default: d.copyRelativePath)
            newFile = c.value(.newFile, default: d.newFile)
        }
    }

    public enum AppIconStyle: String, Codable, Sendable {
        case monochrome
        case color
    }

    public struct Appearance: Codable, Equatable, Sendable {
        public var appIconStyle: AppIconStyle

        public init(appIconStyle: AppIconStyle = .monochrome) {
            self.appIconStyle = appIconStyle
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appIconStyle = c.value(.appIconStyle, default: Appearance().appIconStyle)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        version = c.value(.version, default: d.version) // 预留字段：暂无按版本迁移的逻辑
        items = c.value(.items, default: d.items)
        terminals = Self.lossyList(c, .terminals) ?? []
        editors = Self.lossyList(c, .editors) ?? []
        commands = Self.lossyList(c, .commands) ?? d.commands
        defaultTerminal = (try? c.decodeIfPresent(String.self, forKey: .defaultTerminal)) ?? nil
        terminalTemplates = c.value(.terminalTemplates, default: [:])
        appearance = c.value(.appearance, default: d.appearance)
    }

    /// 数组字段逐条容错解码：单条损坏只丢该条，不连带丢弃整个数组——防止手改
    /// 配置时一处笔误静默清空全部条目（enabled 状态、自定义项）。
    /// 键缺失或值不是数组时返回 nil，由调用方决定默认值。
    private static func lossyList<T: Decodable, K: CodingKey>(
        _ c: KeyedDecodingContainer<K>, _ key: K) -> [T]? {
        guard let raw = (try? c.decodeIfPresent([FailableEntry<T>].self, forKey: key)) ?? nil
        else { return nil }
        return raw.compactMap { $0.value }
    }
}

/// 解码永不失败的包装：条目损坏时 value 为 nil（配合 lossyList 做逐条容错）。
private struct FailableEntry<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

extension KeyedDecodingContainer {
    /// 键缺失、显式 null、或值类型不符 → 回退默认值。
    /// （`try?` 覆盖含 `??` 的整个右侧表达式，故需两级 `??` 分别兜「解码抛错」与「键缺失」。）
    func value<T: Decodable>(_ key: Key, default d: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key) ?? d) ?? d
    }
}

extension Settings {
    /// 把已安装的内置 App 并入列表：新增缺失项、去重、内置在前（按内置顺序）、
    /// 自定义在后（保留添加顺序）；保留既有 enabled 状态与被卸载的内置条目。
    public mutating func reconcile(
        installedTerminals: [KnownApp],
        installedEditors: [KnownApp]
    ) {
        terminals = Self.reconcileList(terminals, installed: installedTerminals, builtinOrder: KnownApps.terminals)
        editors = Self.reconcileList(editors, installed: installedEditors, builtinOrder: KnownApps.editors)
    }

    static func reconcileList(_ existing: [AppEntry], installed: [KnownApp],
                              builtinOrder: [KnownApp]) -> [AppEntry] {
        var byId: [String: AppEntry] = [:]
        var order: [String] = []
        for e in existing where byId[e.bundleId] == nil {
            byId[e.bundleId] = e
            order.append(e.bundleId)
        }
        for app in installed where byId[app.bundleId] == nil {
            byId[app.bundleId] = AppEntry(bundleId: app.bundleId, name: app.displayName,
                                          custom: false, enabled: true)
            order.append(app.bundleId)
        }
        let builtinIndex = Dictionary(
            builtinOrder.enumerated().map { ($1.bundleId, $0) },
            uniquingKeysWith: { first, _ in first }) // 防御：内置清单万一有重复 bundleId 不崩
        let installedById = Dictionary(
            installed.map { ($0.bundleId, $0) },
            uniquingKeysWith: { first, _ in first })
        for id in order {
            if let idx = builtinIndex[id] {
                byId[id]?.custom = false
                if let installedName = installedById[id]?.displayName {
                    byId[id]?.name = installedName
                } else if byId[id]?.name.isEmpty != false {
                    byId[id]?.name = builtinOrder[idx].displayName
                }
            } else {
                byId[id]?.custom = true
            }
        }
        let entries = order.compactMap { byId[$0] }
        let builtins = entries.filter { !$0.custom }
            .sorted { (builtinIndex[$0.bundleId] ?? .max) < (builtinIndex[$1.bundleId] ?? .max) }
        let customs = entries.filter { $0.custom } // 保留插入顺序
        return builtins + customs
    }

    /// 迁移/防御旧配置：命令名作为执行协议的唯一键，必须非空且不重复；
    /// id 作为 UI 稳定身份，也必须非空且不重复。
    /// 空名使用 defaultName；重复名称在原名后追加 2、3...，保留命令内容与顺序。
    /// 空 id 或重复 id 的后续项会生成新 UUID；已有唯一 id 保持不变。
    public mutating func normalizeCommandNames(defaultName: String) {
        var usedNames: Set<String> = []
        var usedIds: Set<String> = []
        for i in commands.indices {
            if commands[i].id.isEmpty || usedIds.contains(commands[i].id) {
                commands[i].id = UUID().uuidString
            }
            usedIds.insert(commands[i].id)

            let trimmed = commands[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.isEmpty ? defaultName : trimmed
            let unique = Self.uniqueName(base: base, used: usedNames)
            commands[i].name = unique
            usedNames.insert(unique)
        }
    }

    private static func uniqueName(base: String, used: Set<String>) -> String {
        var name = base
        var n = 1
        while used.contains(name) {
            n += 1
            name = "\(base)\(n)"
        }
        return name
    }
}

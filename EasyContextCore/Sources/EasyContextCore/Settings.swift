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
        name = (try? c.decodeIfPresent(String.self, forKey: .name) ?? "") ?? ""
        custom = (try? c.decodeIfPresent(Bool.self, forKey: .custom) ?? false) ?? false
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true) ?? true
    }
}

/// 共享配置（宿主 GUI 与 FinderSync 扩展读写同一份 JSON）。
/// 解码对缺失字段容忍——手改文件少写某项时回退默认值。
public struct Settings: Codable, Equatable, Sendable {
    public var version: Int
    public var items: Items
    public var terminals: [AppEntry]
    public var editors: [AppEntry]
    public var appearance: Appearance

    public init(
        version: Int = 2,
        items: Items = Items(),
        terminals: [AppEntry] = [],
        editors: [AppEntry] = [],
        appearance: Appearance = Appearance()
    ) {
        self.version = version
        self.items = items
        self.terminals = terminals
        self.editors = editors
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
            copyFullPath = (try? c.decodeIfPresent(Bool.self, forKey: .copyFullPath) ?? d.copyFullPath) ?? d.copyFullPath
            copyRelativePath = (try? c.decodeIfPresent(Bool.self, forKey: .copyRelativePath) ?? d.copyRelativePath) ?? d.copyRelativePath
            newFile = (try? c.decodeIfPresent(Bool.self, forKey: .newFile) ?? d.newFile) ?? d.newFile
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
            let d = Appearance()
            appIconStyle = (try? c.decodeIfPresent(AppIconStyle.self, forKey: .appIconStyle) ?? d.appIconStyle) ?? d.appIconStyle
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        version = (try? c.decodeIfPresent(Int.self, forKey: .version) ?? d.version) ?? d.version
        items = (try? c.decodeIfPresent(Items.self, forKey: .items) ?? d.items) ?? d.items
        terminals = (try? c.decodeIfPresent([AppEntry].self, forKey: .terminals) ?? []) ?? []
        editors = (try? c.decodeIfPresent([AppEntry].self, forKey: .editors) ?? []) ?? []
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance) ?? d.appearance
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
        let builtinIndex = Dictionary(uniqueKeysWithValues:
            builtinOrder.enumerated().map { ($1.bundleId, $0) })
        for id in order {
            if let idx = builtinIndex[id] {
                byId[id]?.custom = false
                byId[id]?.name = builtinOrder[idx].displayName // 名称以内置清单为准
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

    /// 扩展端：要在菜单显示的条目（启用且当前已安装），按列表顺序。
    public func menuApps(_ list: [AppEntry], isInstalled: (String) -> Bool) -> [AppEntry] {
        list.filter { $0.enabled && isInstalled($0.bundleId) }
    }
}

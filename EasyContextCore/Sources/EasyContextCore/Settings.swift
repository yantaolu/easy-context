import Foundation

/// 共享配置（宿主 GUI 与 FinderSync 扩展读写同一份 JSON）。
/// 解码对缺失字段容忍——手改文件少写某项时回退默认值。
public struct Settings: Codable, Equatable, Sendable {
    public var version: Int
    public var items: Items
    public var terminals: AppSelection
    public var editors: AppSelection
    public var appearance: Appearance

    public init(
        version: Int = 1,
        items: Items = Items(),
        terminals: AppSelection = AppSelection(),
        editors: AppSelection = AppSelection(),
        appearance: Appearance = Appearance()
    ) {
        self.version = version
        self.items = items
        self.terminals = terminals
        self.editors = editors
        self.appearance = appearance
    }

    // 内置菜单项开关
    public struct Items: Codable, Equatable, Sendable {
        public var copyFullPath: Bool
        public var copyRelativePath: Bool
        public var newFile: Bool

        public init(copyFullPath: Bool = true,
                    copyRelativePath: Bool = true,
                    newFile: Bool = true) {
            self.copyFullPath = copyFullPath
            self.copyRelativePath = copyRelativePath
            self.newFile = newFile
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Items()
            copyFullPath = try c.decodeIfPresent(Bool.self, forKey: .copyFullPath) ?? d.copyFullPath
            copyRelativePath = try c.decodeIfPresent(Bool.self, forKey: .copyRelativePath) ?? d.copyRelativePath
            newFile = try c.decodeIfPresent(Bool.self, forKey: .newFile) ?? d.newFile
        }
    }

    // 某一类 App（终端/编辑器）的显示选择
    public struct AppSelection: Codable, Equatable, Sendable {
        /// true=显示所有检测到的；false=只显示 enabled 里且确实装了的（按 enabled 顺序）
        public var showAll: Bool
        public var enabled: [String]

        public init(showAll: Bool = true, enabled: [String] = []) {
            self.showAll = showAll
            self.enabled = enabled
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = AppSelection()
            showAll = try c.decodeIfPresent(Bool.self, forKey: .showAll) ?? d.showAll
            enabled = try c.decodeIfPresent([String].self, forKey: .enabled) ?? d.enabled
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
            appIconStyle = try c.decodeIfPresent(AppIconStyle.self, forKey: .appIconStyle) ?? d.appIconStyle
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        items = try c.decodeIfPresent(Items.self, forKey: .items) ?? d.items
        terminals = try c.decodeIfPresent(AppSelection.self, forKey: .terminals) ?? d.terminals
        editors = try c.decodeIfPresent(AppSelection.self, forKey: .editors) ?? d.editors
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? d.appearance
    }
}

extension Settings {
    /// 给定某类已检测到的 App，按配置算出最终要显示的列表（含顺序）。
    public func visibleApps(_ all: [KnownApp], selection: AppSelection) -> [KnownApp] {
        if selection.showAll { return all }
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.bundleId, $0) })
        return selection.enabled.compactMap { byId[$0] }
    }
}

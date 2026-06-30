import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var copyFullPathEnabled: Bool
    public var copyRelativePathEnabled: Bool
    public var newFileEnabled: Bool
    public var enabledTerminalBundleIds: [String]
    public var enabledEditorBundleIds: [String]
    public var defaultTemplate: FileTemplate

    public init(
        copyFullPathEnabled: Bool = true,
        copyRelativePathEnabled: Bool = true,
        newFileEnabled: Bool = true,
        enabledTerminalBundleIds: [String] = [],
        enabledEditorBundleIds: [String] = [],
        defaultTemplate: FileTemplate = .blank
    ) {
        self.copyFullPathEnabled = copyFullPathEnabled
        self.copyRelativePathEnabled = copyRelativePathEnabled
        self.newFileEnabled = newFileEnabled
        self.enabledTerminalBundleIds = enabledTerminalBundleIds
        self.enabledEditorBundleIds = enabledEditorBundleIds
        self.defaultTemplate = defaultTemplate
    }

    public static let appGroupId = "group.com.luyantao.easycontext"
    private static let storageKey = "settings"

    public static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

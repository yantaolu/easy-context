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
}

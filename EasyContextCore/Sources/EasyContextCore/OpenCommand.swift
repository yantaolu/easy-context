import Foundation

public struct ProcessSpec: Equatable, Sendable {
    public let launchPath: String
    public let arguments: [String]

    public init(launchPath: String, arguments: [String]) {
        self.launchPath = launchPath
        self.arguments = arguments
    }
}

public enum OpenCommand {
    /// 构造 `open -b <bundleId> <dir>`：用目标目录打开该 App
    /// （编辑器视为项目目录、终端视为工作目录）。
    public static func open(app: KnownApp, directory: URL) -> ProcessSpec {
        ProcessSpec(launchPath: "/usr/bin/open",
                    arguments: ["-b", app.bundleId, directory.path])
    }
}

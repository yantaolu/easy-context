import Foundation

public struct RelativePathResolver {
    private let gitMarkerExists: (URL) -> Bool
    private let homeDirectory: URL

    public init(gitMarkerExists: @escaping (URL) -> Bool, homeDirectory: URL) {
        self.gitMarkerExists = gitMarkerExists
        self.homeDirectory = homeDirectory
    }

    public init(fileManager: FileManager = .default) {
        // `.git` 存在即可，不限类型：普通仓库是目录，worktree / submodule 下是文件（gitlink）。
        self.gitMarkerExists = { fileManager.fileExists(atPath: $0.path) }
        self.homeDirectory = fileManager.homeDirectoryForCurrentUser
    }

    /// 从 url 向上（含自身目录）查找第一个含 `.git`（目录或 gitlink 文件）的祖先。
    public func gitRoot(for url: URL) -> URL? {
        var current = url.standardizedFileURL
        while true {
            if gitMarkerExists(current.appendingPathComponent(".git")) {
                // Normalize via .path to strip trailing slash added by deletingLastPathComponent()
                return URL(fileURLWithPath: current.path)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil } // 到文件系统根
            current = parent
        }
    }

    /// git 仓库内：相对仓库根；否则回退 `~/...`；再否则返回绝对路径。
    public func relativePath(for url: URL) -> String {
        let target = url.standardizedFileURL
        if let root = gitRoot(for: target) {
            return Self.relative(from: root, to: target)
        }
        let home = homeDirectory.standardizedFileURL
        if target.path == home.path || target.path.hasPrefix(home.path + "/") {
            return "~/" + Self.relative(from: home, to: target)
        }
        return target.path
    }

    static func relative(from base: URL, to target: URL) -> String {
        let baseComponents = base.pathComponents
        let targetComponents = target.pathComponents
        var i = 0
        while i < baseComponents.count && i < targetComponents.count
            && baseComponents[i] == targetComponents[i] {
            i += 1
        }
        let ups = Array(repeating: "..", count: baseComponents.count - i)
        let downs = Array(targetComponents[i...])
        let parts = ups + downs
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}

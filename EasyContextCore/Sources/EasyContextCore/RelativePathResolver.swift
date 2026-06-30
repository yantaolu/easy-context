import Foundation

public struct RelativePathResolver {
    private let directoryExists: (URL) -> Bool
    private let homeDirectory: URL

    public init(directoryExists: @escaping (URL) -> Bool, homeDirectory: URL) {
        self.directoryExists = directoryExists
        self.homeDirectory = homeDirectory
    }

    public init(fileManager: FileManager = .default) {
        self.directoryExists = { url in
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
        self.homeDirectory = fileManager.homeDirectoryForCurrentUser
    }

    /// 从 url 向上（含自身目录）查找第一个含 `.git` 的祖先。
    public func gitRoot(for url: URL) -> URL? {
        var current = url.standardizedFileURL
        while true {
            if directoryExists(current.appendingPathComponent(".git")) {
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

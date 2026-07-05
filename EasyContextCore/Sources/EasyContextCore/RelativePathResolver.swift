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
        // 沙盒扩展里 homeDirectoryForCurrentUser 会被重定向到容器路径，「~/」回退
        // 将永远匹配不上真实家目录 → 与 ConfigStore 一致，用 getpwuid 取真实家目录。
        self.homeDirectory = URL(fileURLWithPath: ConfigStore.realHomeDirectory(),
                                 isDirectory: true)
    }

    /// 从 url 向上（含自身目录）查找第一个含 `.git`（目录或 gitlink 文件）的祖先。
    ///
    /// ⚠️ 用**纯路径字符串**向上走，不用 URL.deletingLastPathComponent：Finder 递给
    /// 扩展的是 NSURL 桥接 URL，它在根目录上 deletingLastPathComponent 会追加 "../"
    /// 而不是停在 "/"（路径 /../../.. 无限增长），「parent == current」永不成立 →
    /// 死循环 + 内存爆涨。NSString.deletingLastPathComponent 是纯字符串操作，
    /// "/" 的父仍是 "/"，必然收敛。
    public func gitRoot(for url: URL) -> URL? {
        var current = url.standardizedFileURL.path
        while true {
            if gitMarkerExists(URL(fileURLWithPath: current).appendingPathComponent(".git")) {
                return URL(fileURLWithPath: current)
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { return nil } // 到文件系统根（"/" 的父仍是 "/"）
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
        if target.path == home.path { return "~" } // 家目录本身（如在 ~ 空白处右键）
        if target.path.hasPrefix(home.path + "/") {
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

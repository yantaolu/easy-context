import Foundation

public struct TargetDirectoryResolver {
    private let isDirectory: (URL) -> Bool

    public init(isDirectory: @escaping (URL) -> Bool) {
        self.isDirectory = isDirectory
    }

    public init(fileManager: FileManager = .default) {
        self.isDirectory = { url in
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
    }

    /// 选中目录则返回自身，选中文件则返回其父目录。
    public func directory(for url: URL) -> URL {
        if isDirectory(url) { return url }
        // deletingLastPathComponent() adds a trailing slash; URL.path strips it for file URLs
        return URL(fileURLWithPath: url.deletingLastPathComponent().path)
    }
}

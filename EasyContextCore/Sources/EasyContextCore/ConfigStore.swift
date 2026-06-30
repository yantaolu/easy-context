import Foundation

public struct ConfigStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认指向两端共享的真实路径：~/.easy-context/config.json
    ///
    /// 关键：用 getpwuid(getuid()) 取**真实**家目录。沙盒扩展里
    /// NSHomeDirectory() / NSHomeDirectoryForUser() 会被重定向到容器，导致
    /// 宿主与扩展读到不同文件、配置“不生效”；getpwuid 读的是用户数据库，
    /// 沙盒不重定向，两端都得到 /Users/<用户>（在 /Users/ 下，已被扩展的
    /// temporary-exception entitlement 放行）。
    public init() {
        let home = Self.realHomeDirectory()
        self.fileURL = URL(fileURLWithPath: home)
            .appendingPathComponent(".easy-context/config.json")
    }

    static func realHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    public var path: String { fileURL.path }

    public func hasStored() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    public func save(_ settings: Settings) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}

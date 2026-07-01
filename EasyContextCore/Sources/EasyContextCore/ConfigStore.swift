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

    /// 与 config.json 同目录的内置模板参考文件（只读用途）。
    public var templatesReferenceURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("terminal-templates.reference.json")
    }

    /// 写出内置终端启动模板参考（每次启动覆盖生成，best-effort，失败静默）。
    /// 用户不知道 bundleId / 内置模板长啥样，照此文件复制到 config.json 的
    /// terminalTemplates 里即可覆盖修改。
    public func writeTemplatesReference(builtin: [String: String]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = TemplatesReference(
            note: "内置终端启动模板参考（只读；每次启动自动覆盖，改这里无效）。"
                + "要覆盖某终端：把它的 bundleId 与模板复制到 config.json 的 terminalTemplates 里修改。"
                + "占位符 {dir}=当前目录、{cmd}=命令（执行时替换为 \"$EC_DIR\"/\"$EC_CMD\"，勿自行加引号）；"
                + "可用 $EC_SHELL=用户登录 shell。值只走环境变量，天然免注入。",
            templates: builtin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload) {
            try? data.write(to: templatesReferenceURL, options: .atomic)
        }
    }

    private struct TemplatesReference: Encodable {
        let note: String
        let templates: [String: String]
        enum CodingKeys: String, CodingKey {
            case note = "_说明"
            case templates
        }
    }
}

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
        realUserField(\.pw_dir) ?? NSHomeDirectory()
    }

    /// 用可重入的 getpwuid_r 读用户数据库字段（扩展里可能在 XPC 工作线程与主线程
    /// 并发调用；宿主用它取登录 shell）。pw_* 指针指向 buffer 内部，须在闭包内完成拷贝。
    public static func realUserField(_ field: KeyPath<passwd, UnsafeMutablePointer<CChar>?>) -> String? {
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 4096)
        return buffer.withUnsafeMutableBufferPointer { buf -> String? in
            guard getpwuid_r(getuid(), &pwd, buf.baseAddress, buf.count, &result) == 0,
                  result != nil, let value = pwd[keyPath: field] else { return nil }
            return String(cString: value)
        }
    }

    public var path: String { fileURL.path }

    public func hasStored() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// 文件指纹（修改时间 + 大小），用于识别 config.json 是否被外部改过。
    /// 文件不存在时为 nil。save 用 .atomic 写盘（换 inode，mtime 必变）→ 足以判定变更。
    public struct FileToken: Equatable {
        public let mtime: Date
        public let size: Int
    }

    public func fileToken() -> FileToken? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int
        else { return nil }
        return FileToken(mtime: mtime, size: size)
    }

    /// 加载结果，区分「文件缺失」与「文件损坏」，供宿主避免用默认值覆盖损坏文件。
    public enum LoadOutcome: Equatable {
        case ok(Settings)
        case missing          // 文件不存在 → 正常用默认
        case corrupt          // 文件在但读/解码失败 → 用默认但别覆盖，先备份
    }

    public func loadOutcome() -> LoadOutcome {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .missing }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return .corrupt }
        return .ok(decoded)
    }

    public func load() -> Settings {
        if case .ok(let s) = loadOutcome() { return s }
        return Settings()
    }

    /// 把损坏的配置文件备份到 config.json.bak（覆盖旧备份），保留用户可修复的原文。
    @discardableResult
    public func backupCorruptFile() -> URL? {
        let bak = fileURL.deletingLastPathComponent().appendingPathComponent("config.json.bak")
        try? FileManager.default.removeItem(at: bak)
        do { try FileManager.default.copyItem(at: fileURL, to: bak); return bak }
        catch { return nil }
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
    /// terminalTemplates 里即可覆盖修改。说明用英文（配置文件的 lingua franca）。
    public func writeTemplatesReference(builtin: [String: String]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = TemplatesReference(
            note: "Built-in terminal launch template reference (read-only; regenerated on every launch, edits here have no effect). "
                + "To override a terminal, copy its bundleId and template into \"terminalTemplates\" in config.json and edit there. "
                + "Placeholders: {dir} = target directory, {cmd} = command; they are replaced with \"$EC_DIR\"/\"$EC_CMD\" at run time, so do not add quotes yourself. "
                + "$EC_SHELL = the user's login shell. Values travel via environment variables only, immune to shell injection.",
            templates: builtin)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload) {
            try? data.write(to: templatesReferenceURL, options: .atomic)
        }
    }

    // MARK: - IPC token（挡外部/网页伪造 easycontext:// URL）
    //
    // 与 config.json 同目录的 .ipc-token（0600）。扩展把它带进 URL、宿主比对。
    // 网页/其它 app 读不到此文件 → 无法伪造有效 URL。（同 UID 进程能读，但那已具
    // 用户权限、不在威胁模型内。）
    public var ipcTokenURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(".ipc-token")
    }

    /// 只读现有 token（不生成）。供沙盒扩展用。
    public func readIPCToken() -> String {
        guard let t = try? String(contentsOf: ipcTokenURL, encoding: .utf8) else { return "" }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 读，缺失则生成并以 0600 写入。宿主启动时调用；扩展在发 IPC URL 前也调用
    /// （扩展的 entitlement 可写 ~/.easy-context），消除「宿主从未运行 → token 缺失
    /// → 首次点击静默失败」。
    @discardableResult
    public func ensureIPCToken() -> String {
        let existing = readIPCToken()
        if !existing.isEmpty { return existing }
        let token = UUID().uuidString
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 创建即 0600，避免「先写后 chmod」之间的可读窗口。
        FileManager.default.createFile(atPath: ipcTokenURL.path, contents: Data(token.utf8),
                                       attributes: [.posixPermissions: 0o600])
        // 写完回读、以盘上实际内容为准：两端并发首建时后写者胜，双方都回读即收敛到
        // 同一 token（不回读会出现「扩展带 A、宿主读 B」的一次性校验失败）；
        // 写盘失败时返回空串，调用方 fail-closed。
        return readIPCToken()
    }

    private struct TemplatesReference: Encodable {
        let note: String
        let templates: [String: String]
        enum CodingKeys: String, CodingKey {
            case note = "_note"
            case templates
        }
    }
}

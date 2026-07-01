import Foundation

/// 一条可在终端运行的命令（如 Claude → `claude`）。
public struct CommandEntry: Codable, Equatable, Sendable, Identifiable {
    public var name: String       // 显示名，也作 id / URL 里的引用键
    public var command: String    // 实际命令行
    public var enabled: Bool

    public var id: String { name }

    public init(name: String, command: String, enabled: Bool = true) {
        self.name = name
        self.command = command
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        command = try c.decode(String.self, forKey: .command)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true) ?? true
    }
}

/// 终端启动模板与默认终端解析。
///
/// 模板是一条命令，带占位符 `{dir}`（目录）、`{cmd}`（命令）。执行时宿主把真实
/// 目录/命令放进环境变量 EC_DIR / EC_CMD，并把占位符替换为 `"$EC_DIR"`/`"$EC_CMD"`
/// 后 `/bin/sh -c` 执行——值全程走环境变量、绝不拼进命令串，天然免注入。
public enum TerminalLaunch {
    public static let systemTerminalBundleId = "com.apple.Terminal"

    /// 内置默认模板（bundleId -> 模板）。AppleScript 类直接用 system attribute 读环境。
    public static let builtinTemplates: [String: String] = [
        "com.mitchellh.ghostty":
            "open -na Ghostty --args --working-directory={dir} -e {cmd}",
        "net.kovidgoyal.kitty":
            "open -na kitty --args --directory {dir} {cmd}",
        "com.github.wez.wezterm":
            "open -na WezTerm --args start --cwd {dir} -- {cmd}",
        "org.alacritty":
            "open -na Alacritty --args --working-directory {dir} -e {cmd}",
        "com.apple.Terminal":
            "osascript -e 'tell application \"Terminal\" to do script "
            + "\"cd \" & quoted form of (system attribute \"EC_DIR\") & \" && \" "
            + "& (system attribute \"EC_CMD\")'",
        "com.googlecode.iterm2":
            "osascript -e 'tell application \"iTerm\" to tell (create window with default profile) "
            + "to tell current session to write text "
            + "\"cd \" & quoted form of (system attribute \"EC_DIR\") & \" && \" "
            + "& (system attribute \"EC_CMD\")'",
    ]

    /// 取某终端的启动模板：用户覆盖优先，否则内置默认，都没有返回 nil。
    public static func template(for bundleId: String, overrides: [String: String]) -> String? {
        overrides[bundleId] ?? builtinTemplates[bundleId]
    }

    /// 把模板里的占位符替换为环境变量引用（值不参与拼接，故免转义/免注入）。
    public static func render(_ template: String) -> String {
        template
            .replacingOccurrences(of: "{dir}", with: "\"$EC_DIR\"")
            .replacingOccurrences(of: "{cmd}", with: "\"$EC_CMD\"")
    }

    /// 解析用于运行命令的默认终端（返回 bundleId）。
    /// - eligible：已启用且已安装的终端（按列表顺序）。
    /// 规则：preferred 若在 eligible 中→用它；否则用第一个 eligible；都没有→系统默认终端。
    public static func resolveDefaultTerminal(eligible: [AppEntry], preferred: String?) -> String {
        if let preferred, eligible.contains(where: { $0.bundleId == preferred }) {
            return preferred
        }
        return eligible.first?.bundleId ?? systemTerminalBundleId
    }
}

import Foundation

/// 一条可在终端运行的命令（如 Claude → `claude`）。
///
/// `id` 是稳定标识（UUID）：既是 SwiftUI 列表身份，也是 easycontext:// URL
/// 引用命令的执行协议键——改名不影响执行、不存在改名竞态。宿主启动时会把
/// 解码回填的 id 写盘固化，保证扩展与宿主两端读到同一批 id。
/// `name` 是纯显示文本，可重复、可随意改。
public struct CommandEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String       // 显示名，也作 URL 里的引用键
    public var command: String    // 实际命令行
    public var enabled: Bool

    public init(id: String = UUID().uuidString, name: String, command: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.command = command
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 旧配置无 id → 回填一个（本次会话内稳定，写盘后固化）。
        let decodedId = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
        id = (decodedId?.isEmpty == false ? decodedId! : UUID().uuidString)
        name = try c.decode(String.self, forKey: .name)
        command = try c.decode(String.self, forKey: .command)
        enabled = c.value(.enabled, default: true)
    }

    /// 可运行 = 启用且命令串非空。菜单显示与宿主执行共用此口径——
    /// 新增命令默认 command 为空，落盘后不该出现在菜单里（点了必失败）。
    public var isRunnable: Bool {
        enabled && !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 终端启动模板与默认终端解析。
///
/// 模板是一条命令，带占位符 `{dir}`（目录）、`{cmd}`（命令）。执行时宿主把真实
/// 目录/命令放进环境变量 EC_DIR / EC_CMD，并把占位符替换为 `"$EC_DIR"`/`"$EC_CMD"`
/// 后 `/bin/sh -c` 执行——值全程走环境变量、绝不拼进命令串，天然免注入。
///
/// PATH 说明：GUI 启动的进程只有精简 PATH（无 ~/.local/bin 等），`-e` 型终端
/// 直接 exec 会找不到 claude/codex。故这类模板通过用户登录 shell 运行命令
/// `"$EC_SHELL" -lic {cmd}`（-l 登录 + -i 交互 → source .zprofile/.zshrc → PATH 齐全），
/// 与 Terminal.app 的 `do script` 行为一致。$EC_SHELL 由宿主注入（用户登录 shell，
/// csh/tcsh 不支持 -lic 组合参数，宿主端已回退 zsh）。
public enum TerminalLaunch {
    public static let systemTerminalBundleId = "com.apple.Terminal"

    /// 内置默认模板（bundleId -> 模板）。AppleScript 类把 EC_DIR / EC_CMD
    /// 作为两个 argv 传入 `on run argv`，避免 `system attribute` 按区域编码
    /// 重新解码 UTF-8 路径。
    /// GUI 型终端用 `open -nb <bundleId>` 按 bundleId 启动（与全项目的 App 标识体系
    /// 一致，App 被重命名也不失效）。
    public static let builtinTemplates: [String: String] = [
        // Ghostty 1.3.0+ 支持 AppleScript：用 input text 把命令打进交互 shell（非 -e
        // 执行）→ 免「Allow execute」弹框、单窗口、PATH 正确。值作为 argv 传入。
        "com.mitchellh.ghostty":
            appleScriptTemplate("""
            tell application "Ghostty"
                set cfg to new surface configuration
                set initial working directory of cfg to ecDir
                set win to new window with configuration cfg
                input text ecCommand to (terminal 1 of selected tab of win)
                send key "enter" to (terminal 1 of selected tab of win)
            end tell
            """),
        // cmux 官方 Scripting Dictionary：新建 workspace，向其 focused terminal
        // 输入命令，再用 Ghostty action 发送 Enter。目录与命令作为 argv 传入。
        KnownApps.cmuxBundleId:
            appleScriptTemplate("""
            tell application "cmux"
                set workspaceTab to new tab
                set targetTerminal to focused terminal of workspaceTab
                focus targetTerminal
                delay 0.2
                input text ("cd " & quoted form of ecDir & " && " & ecCommand) to targetTerminal
                perform action "text:\\\\x0d" on targetTerminal
            end tell
            """),
        // Muxy 官方 CLI 没有单个 run --cwd 命令。已打开的项目新建 tab；首次打开项目时
        // 复用 Muxy 自动创建的初始 tab，避免得到两个 tab。tab ID 不是 send 所需的
        // pane ID，故给它设置基于 UUID 的
        // 唯一临时标题，再从 list-panes 精确取回对应 pane ID；取到后立即恢复自动标题。
        // 冷启动只重试只读探测（不重复建 tab）；快速失败时每阶段仍等待约 10 秒，
        // 单次探测另有 1 秒上限，避免应用启动较慢时过早报错。
        // CLI 需先在 Muxy → Install CLI 安装。EC_MUXY_CLI 仅供测试/诊断覆盖路径。
        KnownApps.muxyBundleId:
            "MUXY_CLI=${EC_MUXY_CLI:-}; "
            + "if [ -z \"$MUXY_CLI\" ]; then "
            + "for CANDIDATE in /usr/local/bin/muxy \"$HOME/bin/muxy\" \"$HOME/.local/bin/muxy\"; do "
            + "[ -x \"$CANDIDATE\" ] && MUXY_CLI=\"$CANDIDATE\" && break; done; "
            + "[ -n \"$MUXY_CLI\" ] || MUXY_CLI=$(command -v muxy 2>/dev/null || true); fi; "
            + "case \"$MUXY_CLI\" in \"\"|*/Muxy.app/Contents/MacOS/*) "
            + "echo \"Muxy CLI is not installed. Run Muxy -> Install CLI first.\" >&2; exit 1;; esac; "
            + "if [ ! -x \"$MUXY_CLI\" ]; then "
            + "echo \"Muxy CLI is not executable: $MUXY_CLI\" >&2; exit 1; fi; "
            + "/usr/bin/open -b com.muxy.app || exit 1; "
            + "i=0; until MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-projects >/dev/null 2>&1; do "
            + "i=$((i + 1)); if [ \"$i\" -ge 50 ]; then "
            + "MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-projects >&2 || true; "
            + "echo \"Muxy CLI did not become ready\" >&2; exit 1; fi; sleep 0.2; done; "
            + "MUXY_PROJECT_WAS_OPEN=0; "
            + "if MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-projects 2>/dev/null "
            + "| /usr/bin/awk -F \"\\t\" "
            + "'$3 == ENVIRON[\"EC_DIR\"] { found=1 } END { exit !found }'; then "
            + "MUXY_PROJECT_WAS_OPEN=1; fi; "
            + "MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" \"$EC_DIR\" || exit 1; "
            + "i=0; until MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-projects 2>/dev/null "
            + "| /usr/bin/awk -F \"\\t\" "
            + "'$3 == ENVIRON[\"EC_DIR\"] { found=1 } END { exit !found }'; do "
            + "i=$((i + 1)); if [ \"$i\" -ge 50 ]; then "
            + "MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-projects >&2 || true; "
            + "echo \"Muxy did not become ready for $EC_DIR\" >&2; exit 1; fi; "
            + "sleep 0.2; done; "
            + "if [ \"$MUXY_PROJECT_WAS_OPEN\" = 1 ]; then "
            + "TAB_ID=$(\"$MUXY_CLI\" new-tab --project \"$EC_DIR\") || exit 1; "
            + "else i=0; TAB_ID=; while [ -z \"$TAB_ID\" ]; do "
            + "TAB_ID=$(MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-tabs --project \"$EC_DIR\" 2>/dev/null "
            + "| /usr/bin/awk -F \"\\t\" '$3 == \"terminal\" && $5 == \"true\" { print $2; exit }'); "
            + "i=$((i + 1)); if [ \"$i\" -ge 50 ]; then "
            + "echo \"Muxy did not expose the initial tab for $EC_DIR\" >&2; exit 1; fi; "
            + "[ -n \"$TAB_ID\" ] || sleep 0.2; done; fi; "
            + "case \"$TAB_ID\" in \"\"|*[!0-9A-Fa-f-]*) "
            + "echo \"Muxy returned an invalid tab ID: $TAB_ID\" >&2; exit 1;; esac; "
            + "EC_MUXY_TOKEN=easycontext-$TAB_ID; export EC_MUXY_TOKEN; "
            + "MUXY_TAB_RENAMED=1; "
            + "cleanup_muxy_title() { if [ \"$MUXY_TAB_RENAMED\" = 1 ]; then "
            + "\"$MUXY_CLI\" tab rename \"$TAB_ID\" >/dev/null 2>&1 || true; fi; }; "
            + "trap cleanup_muxy_title 0; "
            + "if ! \"$MUXY_CLI\" tab rename \"$TAB_ID\" \"$EC_MUXY_TOKEN\" >/dev/null; then "
            + "echo \"Muxy could not identify the new tab: $TAB_ID\" >&2; exit 1; fi; "
            + "i=0; PANE=; while [ -z \"$PANE\" ]; do "
            + "PANE=$(MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-panes 2>/dev/null "
            + "| /usr/bin/awk -F \"\\t\" "
            + "'$2 == ENVIRON[\"EC_MUXY_TOKEN\"] && $3 == ENVIRON[\"EC_DIR\"] { print $1; exit }'); "
            + "i=$((i + 1)); if [ \"$i\" -ge 50 ]; then "
            + "echo \"Muxy did not expose a pane for $EC_DIR\" >&2; exit 1; fi; "
            + "[ -n \"$PANE\" ] || sleep 0.2; done; "
            + "cleanup_muxy_title; MUXY_TAB_RENAMED=0; trap - 0; "
            + "\"$MUXY_CLI\" send --pane \"$PANE\" \"$EC_CMD\" && "
            + "\"$MUXY_CLI\" send-keys --pane \"$PANE\" Enter",
        "io.appmakes.otty":
            // Otty 1.4.1+ 官方 CLI：绝不向既有 pane 输入文本。先用只读 selector
            // 探测当前窗口；有窗口时由 tab new 原子地创建 tab 并传入 cwd/command。
            // 仅当探测和实际创建之间窗口被关掉（selector-not-found，exit 4）时，
            // 才允许回退到 open；其它错误 fail-closed，避免重复执行命令。
            // EC_TERMINAL_APP 由宿主按 bundle ID 注入；EC_OTTY_CLI 仅供测试/诊断覆盖。
            "OTTY_CLI=${EC_OTTY_CLI:-}; "
            + "if [ -z \"$OTTY_CLI\" ]; then OTTY_CLI=\"${EC_TERMINAL_APP:-}/Contents/MacOS/otty-cli\"; fi; "
            + "if [ ! -x \"$OTTY_CLI\" ]; then "
            + "echo \"Otty CLI is unavailable: $OTTY_CLI\" >&2; exit 1; fi; "
            + "if \"$OTTY_CLI\" window show current >/dev/null 2>&1; then "
            + "\"$OTTY_CLI\" tab new --window current --cwd \"$EC_DIR\" --command \"$EC_CMD\"; "
            + "OTTY_STATUS=$?; "
            + "if [ \"$OTTY_STATUS\" -eq 4 ]; then "
            + "\"$OTTY_CLI\" open \"$EC_DIR\" --command \"$EC_CMD\"; "
            + "else exit \"$OTTY_STATUS\"; fi; "
            + "else \"$OTTY_CLI\" open \"$EC_DIR\" --command \"$EC_CMD\"; fi",
        "net.kovidgoyal.kitty":
            "open -nb net.kovidgoyal.kitty --args --directory {dir} \"$EC_SHELL\" -lic {cmd}",
        "com.github.wez.wezterm":
            "open -nb com.github.wez.wezterm --args start --cwd {dir} -- \"$EC_SHELL\" -lic {cmd}",
        "org.alacritty":
            "open -nb org.alacritty --args --working-directory {dir} -e \"$EC_SHELL\" -lic {cmd}",
        "com.apple.Terminal":
            appleScriptTemplate("""
            tell application "Terminal"
                do script ("cd " & quoted form of ecDir & " && " & ecCommand)
            end tell
            """),
        "com.googlecode.iterm2":
            appleScriptTemplate("""
            tell application "iTerm"
                tell (create window with default profile)
                    tell current session to write text ("cd " & quoted form of ecDir & " && " & ecCommand)
                end tell
            end tell
            """),
    ]

    /// 只接受编译期静态 AppleScript body；运行期的目录/命令固定作为
    /// `on run argv` 的两个独立参数传入，绝不拼入 AppleScript source。
    /// 整段 source 作为一个 shell 单引号参数，body 中的单引号也会正确转义。
    static func appleScriptTemplate(_ body: StaticString) -> String {
        let source = """
        on run argv
            set ecDir to item 1 of argv
            set ecCommand to item 2 of argv
        \(String(describing: body))
        end run
        """
        return "/usr/bin/osascript -e \(shellSingleQuoted(source)) -- \"$EC_DIR\" \"$EC_CMD\""
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

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

    /// 过滤出「有启动模板」（内置或用户覆盖）的终端。只有这些能用于运行命令——
    /// 无模板的终端（如 Warp/Hyper）不该出现在执行终端候选里，否则选中后必然失败。
    public static func launchable(_ terminals: [AppEntry],
                                  overrides: [String: String]) -> [AppEntry] {
        terminals.filter { template(for: $0.bundleId, overrides: overrides) != nil }
    }

    /// 解析用于运行命令的默认终端（返回 bundleId）。
    /// - eligible：已安装且有启动模板的终端（按列表顺序，调用方先经 launchable 过滤）。
    /// 规则：preferred 若在 eligible 中→用它；否则用第一个 eligible；都没有→系统默认终端。
    public static func resolveDefaultTerminal(eligible: [AppEntry], preferred: String?) -> String {
        if let preferred, eligible.contains(where: { $0.bundleId == preferred }) {
            return preferred
        }
        return eligible.first?.bundleId ?? systemTerminalBundleId
    }
}

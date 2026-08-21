import Foundation
import XCTest
@testable import EasyContextCore

final class CommandsTests: XCTestCase {
    // MARK: CommandEntry 解码
    func test_commandEntry_decode_defaultsEnabled() throws {
        let s = try JSONDecoder().decode(CommandEntry.self,
                                         from: Data(#"{ "name": "Claude", "command": "claude" }"#.utf8))
        XCTAssertEqual(s.name, "Claude")
        XCTAssertEqual(s.command, "claude")
        XCTAssertTrue(s.enabled) // 缺省
        XCTAssertFalse(s.id.isEmpty) // 旧配置无 id → 回填非空
    }

    // id 稳定：显式提供则保留；两条无 id 的解码各得不同 id
    func test_commandEntry_id_preservedOrBackfilled() throws {
        let withId = try JSONDecoder().decode(CommandEntry.self,
            from: Data(#"{ "id": "fixed-123", "name": "A", "command": "a" }"#.utf8))
        XCTAssertEqual(withId.id, "fixed-123")

        let list = try JSONDecoder().decode([CommandEntry].self,
            from: Data(#"[{"name":"A","command":"a"},{"name":"B","command":"b"}]"#.utf8))
        XCTAssertFalse(list[0].id.isEmpty)
        XCTAssertNotEqual(list[0].id, list[1].id) // 各自独立 id

        // 改名不改 id
        var e = CommandEntry(name: "A", command: "a")
        let original = e.id
        e.name = "B"
        XCTAssertEqual(e.id, original)
    }

    // MARK: 模板取用
    func test_template_overrideWinsThenBuiltinThenNil() {
        let overrides = ["com.mitchellh.ghostty": "my ghostty {dir} {cmd}"]
        XCTAssertEqual(TerminalLaunch.template(for: "com.mitchellh.ghostty", overrides: overrides),
                       "my ghostty {dir} {cmd}")
        // 无覆盖 → 内置
        XCTAssertEqual(TerminalLaunch.template(for: "com.apple.Terminal", overrides: [:]),
                       TerminalLaunch.builtinTemplates["com.apple.Terminal"])
        // 无覆盖无内置 → nil
        XCTAssertNil(TerminalLaunch.template(for: "com.unknown.term", overrides: [:]))
    }

    // MARK: 占位符 → 环境变量引用（免注入）
    func test_render_mapsPlaceholdersToEnvRefs() {
        let out = TerminalLaunch.render("open -na X --args --working-directory={dir} -e {cmd}")
        XCTAssertEqual(out, "open -na X --args --working-directory=\"$EC_DIR\" -e \"$EC_CMD\"")
        // 值不出现在渲染结果里（值只走环境变量）
        XCTAssertFalse(out.contains("{dir}"))
        XCTAssertFalse(out.contains("{cmd}"))
    }

    func test_render_leavesAppleScriptSystemAttributeTemplateUntouched() {
        // AppleScript 模板不含 {dir}/{cmd}，用 system attribute 读环境，render 不改动
        let t = TerminalLaunch.builtinTemplates["com.apple.Terminal"]!
        XCTAssertEqual(TerminalLaunch.render(t), t)
    }

    // -e 型终端（kitty/WezTerm/Alacritty）通过登录 shell 运行命令，保证 GUI 下 PATH 齐全；
    // 按 bundleId 启动（open -nb），App 被重命名也不失效；$EC_SHELL 加引号防路径含空格。
    func test_builtin_dashE_terminals_runViaLoginShell() {
        for id in ["net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty"] {
            let t = TerminalLaunch.builtinTemplates[id]!
            XCTAssertTrue(t.contains("open -nb \(id)"), "\(id) 应按 bundleId 启动")
            XCTAssertTrue(t.contains("\"$EC_SHELL\" -lic {cmd}"), "\(id) 应经 $EC_SHELL -lic 运行命令")
            let r = TerminalLaunch.render(t)
            XCTAssertTrue(r.contains("\"$EC_SHELL\" -lic \"$EC_CMD\""))
            XCTAssertFalse(r.contains("{cmd}"))
        }
    }

    // Ghostty 改用 AppleScript（1.3.0+）：input text 打进交互 shell，非 -e 执行
    func test_builtin_ghostty_usesAppleScript() {
        let t = TerminalLaunch.builtinTemplates["com.mitchellh.ghostty"]!
        XCTAssertTrue(t.contains("osascript"))
        XCTAssertTrue(t.contains("input text (system attribute \"EC_CMD\")"))
        XCTAssertFalse(t.contains("-e $EC_SHELL")) // 不再走 open -e
        // 无 {dir}/{cmd} 占位符（用 system attribute 读环境）→ render 不改动
        XCTAssertEqual(TerminalLaunch.render(t), t)
    }

    // cmux 官方 AppleScript 字典：创建 workspace，定位其 focused terminal，输入并回车。
    func test_builtin_cmux_usesOfficialAppleScriptDictionary() {
        XCTAssertEqual(KnownApps.terminals.first { $0.bundleId == KnownApps.cmuxBundleId }?.displayName,
                       "cmux")
        let t = TerminalLaunch.builtinTemplates[KnownApps.cmuxBundleId]!
        XCTAssertTrue(t.contains("tell application \"cmux\""))
        XCTAssertTrue(t.contains("set workspaceTab to new tab"))
        XCTAssertTrue(t.contains("focused terminal of workspaceTab"))
        XCTAssertTrue(t.contains("focus targetTerminal"))
        XCTAssertTrue(t.contains("delay 0.2"))
        XCTAssertTrue(t.contains("input text"))
        XCTAssertTrue(t.contains("system attribute \"EC_DIR\""))
        XCTAssertTrue(t.contains("system attribute \"EC_CMD\""))
        XCTAssertTrue(t.contains("perform action \"text:\\\\x0d\" on targetTerminal"))
        XCTAssertFalse(t.contains("send_key:enter"))
        XCTAssertEqual(TerminalLaunch.render(t), t)
    }

    // Muxy 通过官方 CLI 打开目标项目，复用初始 tab 或新建一个命令 tab 后发送命令与 Enter；
    // 不用 split-right，避免“运行命令”额外改变用户的分屏布局。
    func test_builtin_muxy_usesCLIToRunCommandInProjectTab() {
        XCTAssertEqual(KnownApps.terminals.first { $0.bundleId == KnownApps.muxyBundleId }?.displayName,
                       "Muxy")
        let t = TerminalLaunch.builtinTemplates[KnownApps.muxyBundleId]!
        XCTAssertTrue(t.contains("EC_MUXY_CLI"))
        XCTAssertTrue(t.contains("/usr/local/bin/muxy"))
        XCTAssertTrue(t.contains("$HOME/.local/bin/muxy"))
        XCTAssertTrue(t.contains("command -v muxy"))
        XCTAssertTrue(t.contains("Muxy CLI is not installed"))
        XCTAssertTrue(t.contains("MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" \"$EC_DIR\""))
        XCTAssertTrue(t.contains("MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-projects"))
        XCTAssertTrue(t.contains("MUXY_PROJECT_WAS_OPEN=0"))
        XCTAssertTrue(t.contains("list-tabs --project \"$EC_DIR\""))
        XCTAssertTrue(t.contains("Muxy did not expose the initial tab"))
        XCTAssertTrue(t.contains("MUXY_CLI_TIMEOUT=1 \"$MUXY_CLI\" list-panes"))
        XCTAssertFalse(t.contains("export MUXY_CLI_TIMEOUT"))
        XCTAssertTrue(t.contains("\"$MUXY_CLI\" \"$EC_DIR\""))
        XCTAssertTrue(t.contains("\"$MUXY_CLI\" list-projects"))
        XCTAssertTrue(t.contains("if [ \"$MUXY_PROJECT_WAS_OPEN\" = 1 ]"))
        XCTAssertTrue(t.contains("TAB_ID=$(\"$MUXY_CLI\" new-tab --project \"$EC_DIR\")"))
        XCTAssertTrue(t.contains("tab rename \"$TAB_ID\" \"$EC_MUXY_TOKEN\""))
        XCTAssertTrue(t.contains("\"$MUXY_CLI\" list-panes"))
        XCTAssertTrue(t.contains("Muxy did not expose a pane"))
        XCTAssertTrue(t.contains("-ge 50"))
        XCTAssertTrue(t.contains("sleep 0.2"))
        XCTAssertTrue(t.contains("\"$MUXY_CLI\" send --pane \"$PANE\" \"$EC_CMD\""))
        XCTAssertTrue(t.contains("\"$MUXY_CLI\" send-keys --pane \"$PANE\" Enter"))
        XCTAssertFalse(t.contains("split-right"))
        XCTAssertEqual(TerminalLaunch.render(t), t)
    }

    /// 行为级覆盖：首次打开复用 Muxy 自动创建的初始 tab；项目已打开时才新建一个 tab。
    /// fake CLI 返回互不相同的 tab/pane ID，并故意把同目录的旧 focused pane 放第一行，
    /// 模板必须借唯一临时标题找到正确 pane。
    func test_builtin_muxy_routesCommandToPaneCreatedForNewTab() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Easy Context Muxy \(UUID().uuidString)")
        let project = root.appendingPathComponent("Project With Spaces")
        let cli = root.appendingPathComponent("fake muxy")
        let log = root.appendingPathComponent("calls.log")
        let state = root.appendingPathComponent("tab-title")
        let ready = root.appendingPathComponent("ready")
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let fakeCLI = #"""
        #!/bin/sh
        COMMAND=$1
        shift
        {
          printf '%s\t%s' "${MUXY_CLI_TIMEOUT:-default}" "$COMMAND"
          for ARG in "$@"; do printf '\t%s' "$ARG"; done
          printf '\n'
        } >> "$FAKE_MUXY_LOG"

        case "$COMMAND" in
          list-projects)
            if [ ! -e "$FAKE_MUXY_READY" ]; then
              exit 1
            fi
            printf 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\tproject\t%s\ttrue\n' "$EC_DIR"
            ;;
          list-tabs)
            printf '0\t11111111-1111-1111-1111-111111111111\tterminal\tTerminal\ttrue\n'
            ;;
          new-tab)
            printf '11111111-1111-1111-1111-111111111111\n'
            ;;
          tab)
            if [ "$1" = rename ] && [ "$#" -eq 3 ]; then
              printf '%s' "$3" > "$FAKE_MUXY_STATE"
            fi
            printf 'ok\n'
            ;;
          list-panes)
            TOKEN=$(cat "$FAKE_MUXY_STATE")
            printf '33333333-3333-3333-3333-333333333333\told\t%s\ttrue\n' "$EC_DIR"
            printf '22222222-2222-2222-2222-222222222222\t%s\t%s\tfalse\n' "$TOKEN" "$EC_DIR"
            ;;
          *)
            if [ "$COMMAND" = "$EC_DIR" ]; then : > "$FAKE_MUXY_READY"; fi
            printf 'ok\n'
            ;;
        esac
        """#
        try fakeCLI.write(to: cli, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", TerminalLaunch.builtinTemplates[KnownApps.muxyBundleId]!]
        var env = ProcessInfo.processInfo.environment
        let command = "printf 'hello world' | sed 's/world/muxy/'"
        env["EC_DIR"] = project.path
        env["EC_CMD"] = command
        env["EC_MUXY_CLI"] = cli.path
        env["FAKE_MUXY_LOG"] = log.path
        env["FAKE_MUXY_STATE"] = state.path
        env["FAKE_MUXY_READY"] = ready.path
        env.removeValue(forKey: "MUXY_CLI_TIMEOUT")
        process.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
        let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(calls.filter { $0.hasPrefix("1\tlist-projects") }.count, 2)
        XCTAssertEqual(calls.filter { $0.hasPrefix("default\tnew-tab") }.count, 0,
                       "首次打开项目应复用 Muxy 自动创建的初始 tab")
        XCTAssertEqual(calls.filter { $0.hasPrefix("1\tlist-tabs") }.count, 1)
        XCTAssertTrue(calls.contains(
            "default\ttab\trename\t11111111-1111-1111-1111-111111111111"
                + "\teasycontext-11111111-1111-1111-1111-111111111111"
        ))
        XCTAssertTrue(calls.contains(
            "default\ttab\trename\t11111111-1111-1111-1111-111111111111"
        ))
        XCTAssertTrue(calls.contains(
            "default\tsend\t--pane\t22222222-2222-2222-2222-222222222222\t\(command)"
        ))
        XCTAssertTrue(calls.contains(
            "default\tsend-keys\t--pane\t22222222-2222-2222-2222-222222222222\tEnter"
        ))
        XCTAssertFalse(calls.contains { $0.contains("33333333-3333-3333-3333-333333333333") })

        // ready 已存在，模拟项目已在运行中的 Muxy 打开：这次应恰好新建一个命令 tab。
        try fm.removeItem(at: log)
        try? fm.removeItem(at: state)
        let second = Process()
        second.executableURL = URL(fileURLWithPath: "/bin/sh")
        second.arguments = ["-c", TerminalLaunch.builtinTemplates[KnownApps.muxyBundleId]!]
        second.environment = env
        let secondError = Pipe()
        second.standardOutput = Pipe()
        second.standardError = secondError
        try second.run()
        second.waitUntilExit()
        let secondErrorText = String(data: secondError.fileHandleForReading.readDataToEndOfFile(),
                                     encoding: .utf8) ?? ""
        XCTAssertEqual(second.terminationStatus, 0, secondErrorText)
        let secondCalls = try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        XCTAssertEqual(secondCalls.filter { $0.hasPrefix("default\tnew-tab") }.count, 1,
                       "已有项目应只新建一个命令 tab")
        XCTAssertEqual(secondCalls.filter { $0.hasPrefix("1\tlist-tabs") }.count, 0)
    }

    func test_builtin_otty_usesAppleScriptDoScript() {
        let t = TerminalLaunch.builtinTemplates["io.appmakes.otty"]!
        XCTAssertTrue(t.contains("tell application \"Otty\" to do script"))
        XCTAssertTrue(t.contains("system attribute \"EC_DIR\""))
        XCTAssertTrue(t.contains("system attribute \"EC_CMD\""))
        XCTAssertEqual(TerminalLaunch.render(t), t)
    }

    // Muxy 之外的内置模板都只有一个窗口/tab 创建入口，不能出现“先打开再新建”的组合。
    func test_builtin_nonMuxyTerminals_createExactlyOneExecutionSurface() {
        let expectedPrimitive: [String: String] = [
            "com.mitchellh.ghostty": "new window with configuration",
            KnownApps.cmuxBundleId: "new tab",
            "io.appmakes.otty": "do script",
            "net.kovidgoyal.kitty": "open -nb",
            "com.github.wez.wezterm": "open -nb",
            "org.alacritty": "open -nb",
            "com.apple.Terminal": "do script",
            "com.googlecode.iterm2": "create window with default profile",
        ]
        for (bundleID, primitive) in expectedPrimitive {
            let template = TerminalLaunch.builtinTemplates[bundleID]!
            XCTAssertEqual(template.components(separatedBy: primitive).count - 1, 1,
                           "\(bundleID) 每次运行应只创建一个窗口或 tab")
        }
    }

    // MARK: 可运行判定（菜单显示与宿主执行共用口径）
    func test_isRunnable_requiresEnabledAndNonEmptyCommand() {
        XCTAssertTrue(CommandEntry(name: "A", command: "claude").isRunnable)
        XCTAssertFalse(CommandEntry(name: "A", command: "").isRunnable)          // 新增未填
        XCTAssertFalse(CommandEntry(name: "A", command: "  \n ").isRunnable)     // 纯空白
        XCTAssertFalse(CommandEntry(name: "A", command: "claude", enabled: false).isRunnable)
    }

    // MARK: 可执行终端过滤（launchable）
    func test_launchable_keepsOnlyTerminalsWithTemplate() {
        let list = [term("com.apple.Terminal"),        // 有内置模板
                    term("dev.warp.Warp-Stable"),      // 无模板 → 剔除
                    term("com.custom.term")]           // 无内置但有用户覆盖 → 保留
        let overrides = ["com.custom.term": "open -nb com.custom.term {dir}"]
        XCTAssertEqual(TerminalLaunch.launchable(list, overrides: overrides).map(\.bundleId),
                       ["com.apple.Terminal", "com.custom.term"])
        // 无覆盖时只剩有内置模板的
        XCTAssertEqual(TerminalLaunch.launchable(list, overrides: [:]).map(\.bundleId),
                       ["com.apple.Terminal"])
    }

    // MARK: 默认终端解析
    private func term(_ id: String) -> AppEntry { AppEntry(bundleId: id, name: id, custom: false, enabled: true) }

    func test_resolve_preferredInEligible() {
        let eligible = [term("a"), term("b")]
        XCTAssertEqual(TerminalLaunch.resolveDefaultTerminal(eligible: eligible, preferred: "b"), "b")
    }

    func test_resolve_preferredNotEligible_fallsBackToFirst() {
        let eligible = [term("a"), term("b")]
        XCTAssertEqual(TerminalLaunch.resolveDefaultTerminal(eligible: eligible, preferred: "gone"), "a")
    }

    func test_resolve_noPreferred_usesFirst() {
        let eligible = [term("a"), term("b")]
        XCTAssertEqual(TerminalLaunch.resolveDefaultTerminal(eligible: eligible, preferred: nil), "a")
    }

    func test_resolve_noneEligible_usesSystemTerminal() {
        XCTAssertEqual(TerminalLaunch.resolveDefaultTerminal(eligible: [], preferred: "x"),
                       TerminalLaunch.systemTerminalBundleId)
    }
}

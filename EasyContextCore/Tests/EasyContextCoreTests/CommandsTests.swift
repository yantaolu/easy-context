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

    // -e 型终端（kitty/WezTerm/Alacritty）通过登录 shell 运行命令，保证 GUI 下 PATH 齐全
    func test_builtin_dashE_terminals_runViaLoginShell() {
        for id in ["net.kovidgoyal.kitty", "com.github.wez.wezterm", "org.alacritty"] {
            let t = TerminalLaunch.builtinTemplates[id]!
            XCTAssertTrue(t.contains("$EC_SHELL -lic {cmd}"), "\(id) 应经 $EC_SHELL -lic 运行命令")
            let r = TerminalLaunch.render(t)
            XCTAssertTrue(r.contains("$EC_SHELL -lic \"$EC_CMD\""))
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

    func test_builtin_otty_usesAppleScriptDoScript() {
        let t = TerminalLaunch.builtinTemplates["io.appmakes.otty"]!
        XCTAssertTrue(t.contains("tell application \"Otty\" to do script"))
        XCTAssertTrue(t.contains("system attribute \"EC_DIR\""))
        XCTAssertTrue(t.contains("system attribute \"EC_CMD\""))
        XCTAssertEqual(TerminalLaunch.render(t), t)
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

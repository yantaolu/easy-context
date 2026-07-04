import XCTest
@testable import EasyContextCore

final class SettingsTests: XCTestCase {
    func test_defaultInit_hasExpectedDefaults() {
        let s = Settings()
        XCTAssertEqual(s.version, 3)
        XCTAssertTrue(s.items.copyFullPath)
        XCTAssertTrue(s.items.copyRelativePath)
        XCTAssertTrue(s.items.newFile)
        XCTAssertEqual(s.terminals, [])
        XCTAssertEqual(s.editors, [])
        // v3：预置 Claude/Codex 命令、默认终端 nil、无模板覆盖
        XCTAssertEqual(s.commands.map(\.name), ["Claude", "Codex"])
        XCTAssertEqual(s.commands.map(\.command), ["claude", "codex"])
        XCTAssertNil(s.defaultTerminal)
        XCTAssertEqual(s.terminalTemplates, [:])
        XCTAssertEqual(s.appearance.appIconStyle, .monochrome)
    }

    func test_decode_partialJSON_fillsDefaults() throws {
        let json = """
        { "terminals": [ { "bundleId": "com.apple.Terminal", "name": "Terminal", "enabled": false } ] }
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertEqual(s.terminals.count, 1)
        XCTAssertEqual(s.terminals[0].bundleId, "com.apple.Terminal")
        XCTAssertFalse(s.terminals[0].enabled)
        XCTAssertFalse(s.terminals[0].custom) // 缺省
        XCTAssertTrue(s.items.copyFullPath)   // 未写→默认
        // v2 旧配置（无 commands 键）加载后回退预置命令
        XCTAssertEqual(s.commands.map(\.name), ["Claude", "Codex"])
        XCTAssertEqual(s.appearance.appIconStyle, .monochrome)
    }

    // 显式空 commands（present but []）应保留为空，不被回退
    func test_decode_emptyCommands_staysEmpty() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{ "commands": [] }"#.utf8))
        XCTAssertEqual(s.commands, [])
    }

    // reconcile：新增缺失内置、去重、内置在前按内置顺序、自定义在后、保留 enabled
    func test_reconcile_addsSortsAndPreserves() {
        let builtinTerminals = KnownApps.terminals
        // 已有：一个内置（iTerm，被用户关掉）+ 一个自定义
        let existing = [
            AppEntry(bundleId: "com.googlecode.iterm2", name: "iTerm", custom: false, enabled: false),
            AppEntry(bundleId: "com.example.MyTerm", name: "MyTerm", custom: true, enabled: true),
        ]
        // 已安装内置：Terminal + iTerm
        let installed = [
            builtinTerminals.first { $0.bundleId == "com.apple.Terminal" }!,
            builtinTerminals.first { $0.bundleId == "com.googlecode.iterm2" }!,
        ]
        let result = Settings.reconcileList(existing, installed: installed, builtinOrder: builtinTerminals)

        // Terminal 在内置清单里排在 iTerm 前 → 顺序 Terminal, iTerm, 然后自定义
        XCTAssertEqual(result.map(\.bundleId),
                       ["com.apple.Terminal", "com.googlecode.iterm2", "com.example.MyTerm"])
        // 新增的 Terminal 默认 enabled
        XCTAssertTrue(result[0].enabled)
        // iTerm 保留用户关闭状态
        XCTAssertFalse(result[1].enabled)
        // 自定义条目保留
        XCTAssertTrue(result[2].custom)
    }

    func test_reconcile_keepsUninstalledBuiltin() {
        let existing = [
            AppEntry(bundleId: "com.apple.Terminal", name: "Terminal", custom: false, enabled: true),
        ]
        // 没有任何已安装内置传入（模拟卸载）
        let result = Settings.reconcileList(existing, installed: [], builtinOrder: KnownApps.terminals)
        XCTAssertEqual(result.map(\.bundleId), ["com.apple.Terminal"]) // 仍保留
    }

    func test_reconcile_usesInstalledDisplayNameForBuiltin() {
        let existing = [
            AppEntry(bundleId: "com.apple.Terminal", name: "Old Terminal", custom: false, enabled: true),
        ]
        let installed = [
            KnownApp(bundleId: "com.apple.Terminal", displayName: "Installed Terminal", category: .terminal),
        ]
        let result = Settings.reconcileList(existing, installed: installed, builtinOrder: KnownApps.terminals)
        XCTAssertEqual(result.first?.name, "Installed Terminal")
    }

    func test_menuApps_filtersEnabledAndInstalled() {
        let list = [
            AppEntry(bundleId: "a", name: "A", enabled: true),
            AppEntry(bundleId: "b", name: "B", enabled: false),
            AppEntry(bundleId: "c", name: "C", enabled: true),
        ]
        let installed: Set<String> = ["a", "b"] // c 未安装
        let result = Settings().menuApps(list, isInstalled: { installed.contains($0) })
        XCTAssertEqual(result.map(\.bundleId), ["a"]) // 仅 a（启用且已安装）
    }
}

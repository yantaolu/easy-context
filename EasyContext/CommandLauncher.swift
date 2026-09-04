import Foundation
import AppKit
import EasyContextCore

/// 处理扩展发来的 easycontext://run?cmd=&dir=&term= —— 在指定终端于目录运行命令。
enum CommandLauncher {
    @MainActor
    static func handleMuxyOpen(_ url: URL) {
        guard url.scheme == "easycontext", url.host == "open-muxy",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dir = comps.queryItems?.first(where: { $0.name == "dir" })?.value,
              case let expectedToken = ConfigStore().readIPCToken(),
              !expectedToken.isEmpty,
              comps.queryItems?.first(where: { $0.name == "t" })?.value == expectedToken
        else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return }
        let marker = "MUXY_PROJECT_WAS_OPEN=0;"
        guard let script = TerminalLaunch.builtinTemplates[KnownApps.muxyBundleId],
              let markerRange = script.range(of: marker) else {
            notify(String(localized: "Run Failed"),
                   "The built-in Muxy launch template is invalid.")
            return
        }
        let openOnly = String(script[..<markerRange.lowerBound]) + "\"$MUXY_CLI\" \"$EC_DIR\""
        run(command: "", dir: dir, template: openOnly)
    }

    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "easycontext", url.host == "run",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }
        let q = comps.queryItems ?? []
        func value(_ name: String) -> String? { q.first { $0.name == name }?.value }
        guard let dir = value("dir"), let term = value("term") else { return }

        let configStore = ConfigStore()
        // 安全①：token 必须匹配（挡网页/其它 app 伪造的 easycontext:// URL）。
        // 校验失败给提示而非静默：合法场景几乎只剩「token 首建竞态/写盘失败」，
        // 重试即可恢复；伪造 URL 触发提示也无害（浏览器打开自定义 scheme 前有确认框）。
        let expected = configStore.readIPCToken()
        guard !expected.isEmpty, value("t") == expected else {
            notify(String(localized: "Cannot Verify Request"),
                   String(localized: "The request could not be verified. Please try again from the right-click menu."))
            return
        }
        // 安全②：目录必须真实存在且是目录（挡任意/伪造路径）。
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue
        else { return }

        var settings = configStore.load() // 权威当前配置
        settings.normalizeCommands(defaultName: String(localized: "Command"))
        // 安全③：命令必须在用户配置里且可运行（不执行 URL 里的任意命令串）。
        // 按稳定 id 查（改名不影响执行）；id 查不到再回退 name——手改配置抹掉 id 时，
        // 扩展内存中随机回填的 id 与宿主重新加载时回填的不同，此时 URL 里的 name
        // 仍能对上；name 也兼容升级期间尚未重启的旧版扩展进程。
        // isRunnable 与菜单显示同口径：禁用或命令串为空都拒绝（挡竞态/伪造 URL）。
        guard value("id") != nil || value("cmd") != nil else { return }
        let byId = value("id").flatMap { id in settings.commands.first { $0.id == id } }
        let byName = value("cmd").flatMap { name in settings.commands.first { $0.name == name } }
        guard let entry = byId ?? byName, entry.isRunnable else {
            notify(String(localized: "Cannot Run"),
                   String(localized: "This command was removed or disabled. Reopen the right-click menu and try again."))
            return
        }
        // 终端必须有模板（内置或用户覆盖）。
        guard let template = TerminalLaunch.template(for: term, overrides: settings.terminalTemplates)
        else {
            notify(String(localized: "Cannot Run"),
                   String(localized: "“\(term)” has no launch template configured. Please add one in EasyContext settings."))
            return
        }
        // Otty 的官方 CLI 位于 App bundle 内。通过 bundle ID 解析实际安装位置，避免
        // 假设 /Applications 或依赖 GUI 进程的 PATH；其它模板也可按需使用该环境变量。
        let terminalAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: term)
        run(command: entry.command, dir: dir, template: template, terminalAppURL: terminalAppURL)
    }

    private static func run(command: String, dir: String, template: String,
                            terminalAppURL: URL? = nil) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", TerminalLaunch.render(template)]
        // 值全程走环境变量，绝不拼进命令串 → 免注入。
        var env = ProcessInfo.processInfo.environment
        env["EC_DIR"] = dir
        env["EC_CMD"] = command
        env["EC_SHELL"] = loginShell() // `-e` 型模板据此走登录 shell 取全 PATH
        env["EC_TERMINAL_APP"] = terminalAppURL?.path ?? ""
        process.environment = env
        // run() 成功只代表 /bin/sh 起来了；osascript/open 的失败（最典型：自动化权限
        // 被用户拒过一次 → 此后永远静默无反应）只体现在退出码/stderr，必须检查并提示。
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do { try process.run() } catch {
            notify(String(localized: "Run Failed"), error.localizedDescription)
            return
        }
        // 与 pluginkit 检测同一模式：先读完 stderr 再等退出。若只在退出回调里读，
        // 子进程 stderr 超过管道缓冲（64KB）时会阻塞在写端、永不退出 → 双方互等卡死，
        // 且每次点击都泄漏一组孤儿进程。闭包捕获 process，顺带保证其存活到退出。
        DispatchQueue.global(qos: .utility).async {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus != 0 else { return }
            let stderr = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in reportRunFailure(stderr: stderr) }
        }
    }

    /// 区分「自动化权限被拒」（osascript -1743）与一般失败：前者给出跳系统设置的引导。
    @MainActor
    private static func reportRunFailure(stderr: String) {
        if stderr.contains("-1743") || stderr.localizedCaseInsensitiveContains("not authorized") {
            let alert = NSAlert()
            alert.messageText = String(localized: "Automation Permission Required")
            alert.informativeText = String(localized: "macOS is blocking Easy Context from controlling the terminal. Enable Easy Context in System Settings → Privacy & Security → Automation, then try again.")
            alert.addButton(withTitle: String(localized: "Open System Settings"))
            alert.addButton(withTitle: String(localized: "OK"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        notify(String(localized: "Run Failed"),
               stderr.isEmpty ? String(localized: "The command exited with an error.") : stderr)
    }

    /// 用户登录 shell（GUI 进程环境里 SHELL 常缺失，故从 passwd 取），兜底 /bin/zsh。
    private static func loginShell() -> String {
        if let path = ConfigStore.realUserField(\.pw_shell), !path.isEmpty {
            // csh/tcsh 不支持 -lic 组合参数（-l 必须单独出现）→ 回退 zsh 保证命令能跑。
            let base = (path as NSString).lastPathComponent
            if base != "csh", base != "tcsh" { return path }
        }
        return "/bin/zsh"
    }

    private static func notify(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

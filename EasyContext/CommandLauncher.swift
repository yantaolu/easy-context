import Foundation
import AppKit
import EasyContextCore

/// 处理扩展发来的 easycontext://run?cmd=&dir=&term= —— 在指定终端于目录运行命令。
enum CommandLauncher {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "easycontext", url.host == "run",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }
        let q = comps.queryItems ?? []
        func value(_ name: String) -> String? { q.first { $0.name == name }?.value }
        guard let cmdName = value("cmd"), let dir = value("dir"), let term = value("term")
        else { return }

        let configStore = ConfigStore()
        // 安全①：token 必须匹配（挡网页/其它 app 伪造的 easycontext:// URL）。
        let expected = configStore.readIPCToken()
        guard !expected.isEmpty, value("t") == expected else { return }
        // 安全②：目录必须真实存在且是目录（挡任意/伪造路径）。
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue
        else { return }

        let settings = configStore.load() // 权威当前配置
        // 安全③：命令必须在用户配置里且启用（按名字查，不执行 URL 里的任意命令串）。
        guard let entry = settings.commands.first(where: { $0.name == cmdName && $0.enabled })
        else { return }
        // 终端必须有模板（内置或用户覆盖）。
        guard let template = TerminalLaunch.template(for: term, overrides: settings.terminalTemplates)
        else {
            notify("无法运行", "“\(term)” 未配置启动模板，请在 EasyContext 设置里为它填写模板。")
            return
        }
        run(command: entry.command, dir: dir, template: template)
    }

    private static func run(command: String, dir: String, template: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", TerminalLaunch.render(template)]
        // 值全程走环境变量，绝不拼进命令串 → 免注入。
        var env = ProcessInfo.processInfo.environment
        env["EC_DIR"] = dir
        env["EC_CMD"] = command
        env["EC_SHELL"] = loginShell() // `-e` 型模板据此走登录 shell 取全 PATH
        process.environment = env
        do { try process.run() } catch { notify("运行失败", error.localizedDescription) }
    }

    /// 用户登录 shell（GUI 进程环境里 SHELL 常缺失，故从 passwd 取），兜底 /bin/zsh。
    private static func loginShell() -> String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell {
            let path = String(cString: sh)
            if !path.isEmpty { return path }
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

import AppKit
import SwiftUI
import EasyContextCore

/// 后台代理型宿主：
/// - 处理 easycontext:// URL（run / newfile）时**不显示**设置窗（无闪烁）；
/// - 用户双击 App / 再次打开时才显示设置窗（并临时露出 Dock 图标）。
/// 用纯 AppKit 手动管窗，避免 SwiftUI 场景在启动/激活时自动开窗。
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var settingsWindow: NSWindow?
    private var launchedForURL = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 后台代理：无 Dock、不自动显示窗口
        setupMenu()
        // 启动即做的一次性初始化（无论是否显示设置窗，URL 校验需要 token）。
        let store = ConfigStore()
        store.ensureIPCToken()
        store.writeTemplatesReference(builtin: TerminalLaunch.builtinTemplates)
        // 冷启动若不是为处理 URL（用户双击打开）→ 显示设置窗。
        // async 让 open(urls:) 先到（URL 冷启动时它在启动序列里送达）。
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.launchedForURL else { return }
            self.showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedForURL = true
        for url in urls { handle(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    private func handle(_ url: URL) {
        Task { @MainActor in
            switch url.host {
            case "run": CommandLauncher.handle(url)
            case "newfile": NewFileLauncher.handle(url)
            default: break
            }
        }
    }

    // MARK: - 设置窗

    private func showSettings() {
        NSApp.setActivationPolicy(.regular) // 打开设置时露出 Dock 图标
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 494),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            win.title = "Easy Context"
            win.contentViewController = NSHostingController(rootView: ContentView())
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 关设置窗 → 退回后台代理（去 Dock 图标）；App 继续跑以处理后续 URL。
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func setupMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "隐藏 Easy Context",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Easy Context",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        // 文件菜单：提供标准「关闭窗口 ⌘W」（走响应链到当前 key 窗口）。
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "关闭窗口",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        // 编辑菜单：让命名面板输入框支持 复制/粘贴/全选 等快捷键。
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }
}

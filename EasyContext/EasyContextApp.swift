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
    private static let settingsFrameName = "SettingsWindow"

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 在 will 阶段注册 GURL 处理器：URL 冷启动的 Apple Event 保证在
        // didFinishLaunching 之前送达 → 后者可同步判断是否要开设置窗，
        // 不再用 DispatchQueue.main.async 赌 open(urls:) 先到的时序。
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 后台代理：无 Dock、不自动显示窗口
        setupMenu()
        // 启动即做的一次性初始化（无论是否显示设置窗，URL 校验需要 token）。
        let store = ConfigStore()
        store.ensureIPCToken()
        store.writeTemplatesReference(builtin: TerminalLaunch.builtinTemplates)
        // 冷启动若不是为处理 URL（用户双击打开）→ 显示设置窗。
        if !launchedForURL { showSettings() }
    }

    // 全部 URL 送达（冷启动/运行中）都走这里；注册了 GURL 处理器后
    // AppKit 不再回调 application(_:open:)。
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReply reply: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: str) else { return }
        // 只有可识别的动作 URL 才算「为处理 URL 而启动」；垃圾 URL 冷启动仍照常
        // 显示设置窗，避免进程无窗静默驻留。须在此同步置位（didFinishLaunching
        // 同步读取，handle 里的 Task 是异步的）。
        if url.host == "run" || url.host == "newfile" { launchedForURL = true }
        handle(url)
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
                contentRect: NSRect(origin: .zero, size: ContentView.preferredSize),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            win.title = "Easy Context"
            win.contentViewController = NSHostingController(rootView: ContentView())
            win.isReleasedWhenClosed = false
            win.delegate = self
            settingsWindow = win
            // 恢复上次位置；只有首次运行（无保存位置）才居中到鼠标所在屏。
            if !win.setFrameUsingName(Self.settingsFrameName) { centerOnActiveScreen(win) }
            win.setFrameAutosaveName(Self.settingsFrameName)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // 居中到「鼠标所在的显示器」（而非主屏），并避开菜单栏/程序坞（visibleFrame）。
    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { window.center(); return }
        let size = window.frame.size
        let x = vf.origin.x + (vf.width - size.width) / 2
        let y = vf.origin.y + (vf.height - size.height) / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
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
        appMenu.addItem(withTitle: String(localized: "Hide Easy Context"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit Easy Context"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        // 文件菜单：提供标准「关闭窗口 ⌘W」（走响应链到当前 key 窗口）。
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.addItem(withTitle: String(localized: "Close Window"),
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        // 编辑菜单：让命名面板输入框支持 撤销/复制/粘贴/全选 等快捷键。
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        // undo:/redo: 无编译期符号，走响应链到字段编辑器的 undoManager。
        editMenu.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }
}

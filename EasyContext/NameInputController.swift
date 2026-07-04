import AppKit

/// 轻量模态命名面板：预填默认文件名、**只选中基名**（保留扩展名），回车确定 / Esc 取消。
enum NameInputController {
    /// 返回用户输入（去空白）或 nil（取消 / 空）。
    @MainActor
    static func prompt(prefill: String) -> String? {
        NameInputPanel(prefill: prefill).run()
    }
}

/// 用自建窗口 + NSApp.runModal，而非 NSAlert——这样能在窗口**显示后**（字段编辑器就绪）
/// 设置选中范围；NSAlert 下选中代码跑在模态 runloop 外、无法生效。
@MainActor
private final class NameInputPanel: NSObject {
    private let window: NSWindow
    private let field: NSTextField
    private let prefill: String

    init(prefill: String) {
        self.prefill = prefill
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 116))

        let label = NSTextField(labelWithString: String(localized: "输入文件名："))
        label.frame = NSRect(x: 20, y: 82, width: 320, height: 18)
        content.addSubview(label)

        field = NSTextField(frame: NSRect(x: 20, y: 50, width: 320, height: 24))
        field.stringValue = prefill
        content.addSubview(field)

        window = NSWindow(contentRect: content.frame,
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.title = String(localized: "新建文件")
        window.contentView = content
        super.init()

        let cancel = NSButton(title: String(localized: "取消"), target: self, action: #selector(onCancel))
        cancel.frame = NSRect(x: 160, y: 12, width: 85, height: 28)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}" // Esc
        content.addSubview(cancel)

        let create = NSButton(title: String(localized: "创建"), target: self, action: #selector(onCreate))
        create.frame = NSRect(x: 255, y: 12, width: 85, height: 28)
        create.bezelStyle = .rounded
        create.keyEquivalent = "\r" // 默认按钮，回车（含输入框内回车）触发
        content.addSubview(create)
    }

    @objc private func onCreate() { NSApp.stopModal(withCode: .OK) }
    @objc private func onCancel() { NSApp.stopModal(withCode: .cancel) }

    func run() -> String? {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 窗口已显示 → 字段编辑器就绪，只选中基名（保留扩展名如 .md）。
        window.makeFirstResponder(field)
        let baseLen = (URL(fileURLWithPath: prefill).deletingPathExtension().lastPathComponent as NSString).length
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: baseLen)

        let code = NSApp.runModal(for: window)
        window.orderOut(nil)
        guard code == .OK else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

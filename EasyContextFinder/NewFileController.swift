import AppKit
import EasyContextCore

struct NewFileController {
    let configStore: ConfigStore

    func run(in directory: URL?) {
        guard let directory else { return }
        let settings = configStore.load()

        let alert = NSAlert()
        alert.messageText = "新建文件"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 28, width: 240, height: 24))
        field.stringValue = "未命名"

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        for t in FileTemplate.allCases { popup.addItem(withTitle: t.displayName) }
        if let idx = FileTemplate.allCases.firstIndex(of: settings.defaultTemplate) {
            popup.selectItem(at: idx)
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        accessory.addSubview(field)
        accessory.addSubview(popup)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let template = FileTemplate.allCases[popup.indexOfSelectedItem]
        let base = field.stringValue.isEmpty ? "未命名" : field.stringValue
        create(base: base, template: template, in: directory)
    }

    private func create(base: String, template: FileTemplate, in directory: URL) {
        let fm = FileManager.default
        let resolver = UniqueNameResolver(exists: { name in
            fm.fileExists(atPath: directory.appendingPathComponent(name).path)
        })
        let name = resolver.uniqueName(base: base, ext: template.fileExtension)
        let fileURL = directory.appendingPathComponent(name)

        do {
            try template.initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            if template.isExecutable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            }
        } catch {
            NSLog("EasyContext newFile failed: \(error)")
        }
    }
}

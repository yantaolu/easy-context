import Foundation
import AppKit
import EasyContextCore

/// 处理 easycontext://newfile?dir=&template=&t= —— 弹命名面板→建文件→在 Finder 选中。
enum NewFileLauncher {
    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "easycontext", url.host == "newfile",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }
        let q = comps.queryItems ?? []
        func value(_ name: String) -> String? { q.first { $0.name == name }?.value }
        guard let dir = value("dir"), let templateRaw = value("template") else { return }

        let store = ConfigStore()
        // 安全：token 必须匹配（挡外部伪造）；目录必须存在且是目录。
        let token = store.readIPCToken()
        guard !token.isEmpty, value("t") == token else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue
        else { return }
        guard let template = FileTemplate(rawValue: templateRaw) else { return }

        guard let name = NameInputController.prompt(prefill: template.defaultFileName) else { return }
        let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
        guard let created = NewFileMaker.create(template: template, in: dirURL, requestedName: name) else {
            let a = NSAlert()
            a.messageText = String(localized: "Failed to Create File")
            a.informativeText = String(localized: "Could not create a file in this folder.")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
            return
        }
        // 在 Finder 里选中新文件——无需自动化权限（NSWorkspace 标准 API）。
        NSWorkspace.shared.activateFileViewerSelecting([created])
    }
}

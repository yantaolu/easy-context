import Foundation
import AppKit
import EasyContextCore

/// 处理 easycontext://newfile?dir=&template=&t= —— 弹命名面板→建文件→在 Finder 选中。
enum NewFileLauncher {
    /// 命名面板显示期间到达的第二个 newfile URL 直接忽略，避免叠出嵌套模态面板
    /// （runModal 期间主队列仍被 drain，Task 会照常进入本函数）。
    @MainActor private static var isPrompting = false

    @MainActor
    static func handle(_ url: URL) {
        guard url.scheme == "easycontext", url.host == "newfile",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return }
        guard !isPrompting else { return }
        let q = comps.queryItems ?? []
        func value(_ name: String) -> String? { q.first { $0.name == name }?.value }
        guard let dir = value("dir"), let templateRaw = value("template") else { return }

        let store = ConfigStore()
        // 安全：token 必须匹配（挡外部伪造）；目录必须存在且是目录。
        // 校验失败给提示而非静默（同 CommandLauncher：合法场景基本只剩 token 首建
        // 竞态/写盘失败，重试即恢复）。
        let token = store.readIPCToken()
        guard !token.isEmpty, value("t") == token else {
            let a = NSAlert()
            a.messageText = String(localized: "Cannot Verify Request")
            a.informativeText = String(localized: "The request could not be verified. Please try again from the right-click menu.")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue
        else { return }
        guard let template = FileTemplate(rawValue: templateRaw) else { return }

        isPrompting = true
        let name = NameInputController.prompt(prefill: template.defaultFileName)
        isPrompting = false
        guard let name else { return }
        let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
        do {
            let created = try NewFileMaker.create(template: template, in: dirURL, requestedName: name)
            // 在 Finder 里选中新文件——无需自动化权限（NSWorkspace 标准 API）。
            NSWorkspace.shared.activateFileViewerSelecting([created])
        } catch {
            let a = NSAlert()
            a.messageText = String(localized: "Failed to Create File")
            // 透传系统错误（权限被拒/只读卷/磁盘满……），NSError 消息自带本地化。
            a.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }
}

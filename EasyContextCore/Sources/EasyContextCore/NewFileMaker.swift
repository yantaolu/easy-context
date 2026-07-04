import Foundation

/// 按模板在目录里创建文件的纯逻辑（宿主与扩展共用）。
public enum NewFileMaker {
    public static var defaultBaseName: String { String(localized: "Untitled", bundle: .module) }

    /// 在 dir 下按模板创建文件：
    /// - requestedName：用户输入的完整文件名（含扩展名）；空则用模板默认名。
    /// - 只取其 lastPathComponent → 防路径穿越（`../x` 之类被削掉）。
    /// - 重名自动加序号，**永不覆盖**；模板决定初始内容与可执行位。
    /// 返回创建的文件 URL，失败返回 nil。
    public static func create(template: FileTemplate, in dir: URL, requestedName: String,
                              fileManager: FileManager = .default) -> URL? {
        let fm = fileManager
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.isEmpty ? template.defaultFileName : trimmed
        // 用 URL 拆基名/扩展名，天然处理隐藏文件（.gitignore 无扩展名）并去掉目录成分。
        let comp = URL(fileURLWithPath: raw)
        let ext = comp.pathExtension
        let base0 = comp.deletingPathExtension().lastPathComponent
        let base = base0.isEmpty ? defaultBaseName : base0

        let resolver = UniqueNameResolver(exists: {
            fm.fileExists(atPath: dir.appendingPathComponent($0).path)
        })
        let finalName = resolver.uniqueName(base: base, ext: ext)
        let fileURL = dir.appendingPathComponent(finalName)
        do {
            try template.initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            if template.isExecutable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            }
            return fileURL
        } catch {
            return nil
        }
    }
}

import Foundation
import EasyContextCore

// 沙盒扩展不能弹模态窗，新建文件直接在目标目录创建（默认名「未命名」，
// 重名自动加序号），用户在访达里自行重命名。
enum NewFileController {
    static func create(template: FileTemplate, in directory: URL) -> URL? {
        let fm = FileManager.default
        let resolver = UniqueNameResolver(exists: { name in
            fm.fileExists(atPath: directory.appendingPathComponent(name).path)
        })
        let name = resolver.uniqueName(base: "未命名", ext: template.fileExtension)
        let fileURL = directory.appendingPathComponent(name)
        do {
            try template.initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            if template.isExecutable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            }
            return fileURL
        } catch {
            NSLog("EasyContext newFile failed at \(fileURL.path): \(error)")
            return nil
        }
    }
}

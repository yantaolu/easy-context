import Foundation

/// 判断当前运行的扩展是不是「正式」那一份。
///
/// 系统里若残留旧版本 / 下载目录 / 废纸篓 / DerivedData 中的 EasyContext.app，访达可能把其中的
/// 扩展也一起加载，右键菜单就会出现两组重复项。扩展据此判断：只有自己所在的 App 就是
/// LaunchServices 认定的默认 App 时才出菜单，多余的副本保持沉默。
public enum ExtensionCopy {
    /// 扩展的宿主 bundle id：扩展 id 去掉末尾的 `.finder`。
    public static func hostBundleIdentifier(extensionBundleIdentifier id: String) -> String? {
        let suffix = ".finder"
        guard id.hasSuffix(suffix), id.count > suffix.count else { return nil }
        return String(id.dropLast(suffix.count))
    }

    /// 扩展 bundle（…/X.app/Contents/PlugIns/Y.appex）所在的 App；结构不符时返回 nil。
    public static func containingApp(ofExtensionAt appex: URL) -> URL? {
        let plugIns = appex.standardizedFileURL.deletingLastPathComponent()
        let contents = plugIns.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard plugIns.lastPathComponent == "PlugIns",
              contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else { return nil }
        return app
    }

    /// 是否应显示菜单。拿不到判断依据（结构不符 / 系统查不到默认 App）时一律放行，
    /// 宁可偶尔重复，也不能让唯一的那份扩展失去菜单。
    public static func isOfficial(extensionAt appex: URL, officialApp: URL?) -> Bool {
        guard let official = officialApp,
              let mine = containingApp(ofExtensionAt: appex) else { return true }
        return canonical(mine) == canonical(official)
    }

    private static func canonical(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

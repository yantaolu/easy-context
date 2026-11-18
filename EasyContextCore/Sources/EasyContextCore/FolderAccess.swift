import Foundation

/// 外置磁盘的识别。macOS 对它们的访问由隐私授权「可移除宗卷」控制
/// （与磁盘是否真的可弹出无关：雷雳 / USB 固定盘同样受控）。
public enum ExternalVolumes {
    /// 判定所需的卷属性（便于测试注入）。
    public struct Traits: Equatable {
        public var isInternal: Bool
        public var isLocal: Bool
        public var isBrowsable: Bool
        public var isRootFileSystem: Bool

        public init(isInternal: Bool, isLocal: Bool, isBrowsable: Bool, isRootFileSystem: Bool) {
            self.isInternal = isInternal
            self.isLocal = isLocal
            self.isBrowsable = isBrowsable
            self.isRootFileSystem = isRootFileSystem
        }
    }

    public static let resourceKeys: [URLResourceKey] = [
        .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsBrowsableKey, .volumeIsRootFileSystemKey,
    ]

    /// 外置、本地（网络卷属另一类授权）、在访达可见、非启动卷。
    public static func isExternal(_ traits: Traits) -> Bool {
        !traits.isInternal && traits.isLocal && traits.isBrowsable && !traits.isRootFileSystem
    }

    /// 从挂载卷中挑出外置盘，保持系统返回的顺序。读不到属性的卷跳过。
    public static func select(_ volumes: [URL], traits: (URL) -> Traits?) -> [URL] {
        volumes.filter { url in traits(url).map(isExternal) ?? false }
    }

    /// 当前挂载的外置盘。
    public static func mounted(fileManager: FileManager = .default) -> [URL] {
        let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys, options: [.skipHiddenVolumes]) ?? []
        return select(volumes) { url in
            guard let v = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  let isInternal = v.volumeIsInternal, let isLocal = v.volumeIsLocal
            else { return nil }
            return Traits(isInternal: isInternal, isLocal: isLocal,
                          isBrowsable: v.volumeIsBrowsable ?? true,
                          isRootFileSystem: v.volumeIsRootFileSystem ?? false)
        }
    }
}

/// 扩展用 LaunchServices 打开目录失败时，交给宿主重试的请求。
///
/// Finder 扩展是后台进程，macOS 不会为它弹出隐私授权询问；未授权时访问被直接拒绝。
/// 宿主是前台 App：它在前台读取目录即可触发询问，获准后自己用目标 App 打开目录。
/// 扩展的文件访问授权归属于宿主 bundle id，两者共用同一条授权。
public struct FolderOpenFailure: Equatable {
    public static let host = "open-error"

    public var appBundleId: String
    public var directories: [String]
    public var errorDomain: String
    public var errorCode: Int

    public init(appBundleId: String, directories: [String], errorDomain: String, errorCode: Int) {
        self.appBundleId = appBundleId
        self.directories = directories
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }

    /// 编码为 `<scheme>://open-error?app=&dir=…&domain=&code=&t=`（dir 可重复）。
    public func url(scheme: String, token: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = Self.host
        comps.queryItems = [URLQueryItem(name: "app", value: appBundleId)]
            + directories.map { URLQueryItem(name: "dir", value: $0) }
            + [URLQueryItem(name: "domain", value: errorDomain),
               URLQueryItem(name: "code", value: String(errorCode)),
               URLQueryItem(name: "t", value: token)]
        return comps.url
    }

    /// 解析并校验 token。scheme / host / token 不符、缺目标 App 或目录时返回 nil。
    public init?(url: URL, scheme: String, expectedToken: String) {
        guard !expectedToken.isEmpty,
              url.scheme == scheme, url.host == Self.host,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "t" })?.value == expectedToken,
              let app = items.first(where: { $0.name == "app" })?.value, !app.isEmpty
        else { return nil }
        let dirs = items.filter { $0.name == "dir" }.compactMap(\.value).filter { !$0.isEmpty }
        guard !dirs.isEmpty else { return nil }
        self.appBundleId = app
        self.directories = dirs
        self.errorDomain = items.first(where: { $0.name == "domain" })?.value ?? ""
        self.errorCode = items.first(where: { $0.name == "code" })?.value.flatMap(Int.init) ?? 0
    }
}

/// 读取目录的结果分类：用于判断隐私授权是否被拒。
public enum FolderAccessProbe: Equatable {
    case granted
    case denied
    case failed

    /// 把 FileManager 抛出的错误归类。权限被拒表现为 Cocoa 257 或 POSIX EPERM/EACCES。
    public static func classify(_ error: Error?) -> FolderAccessProbe {
        guard let error else { return .granted }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError { return .denied }
        let posix = (ns.domain == NSPOSIXErrorDomain ? ns
                     : ns.userInfo[NSUnderlyingErrorKey] as? NSError)
        if let posix, posix.domain == NSPOSIXErrorDomain,
           posix.code == Int(EPERM) || posix.code == Int(EACCES) {
            return .denied
        }
        return .failed
    }

    /// 读取目录内容。未决定的授权会在此触发系统询问并阻塞到用户作答，勿在主线程调用。
    public static func probe(_ path: String, fileManager: FileManager = .default) -> FolderAccessProbe {
        do {
            _ = try fileManager.contentsOfDirectory(atPath: path)
            return .granted
        } catch {
            return classify(error)
        }
    }
}

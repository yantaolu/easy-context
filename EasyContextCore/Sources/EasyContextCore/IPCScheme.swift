import Foundation

/// 扩展 → 宿主 IPC 所用的自定义 URL scheme。
///
/// Release 为 `easycontext`，Debug 为 `easycontext-debug`（project.yml 的 EC_URL_SCHEME），
/// 由宿主与扩展各自的 Info.plist `ECURLScheme` 提供。分开后，开发版扩展发出的请求只会
/// 交给开发版宿主，不会被已安装版接走（反之亦然）——两者签名身份不同，混用会导致隐私授权错配。
public enum IPCScheme {
    public static let infoKey = "ECURLScheme"
    public static let fallback = "easycontext"

    /// 当前进程（宿主或扩展）应使用的 scheme。
    public static var current: String {
        resolve(Bundle.main.object(forInfoDictionaryKey: infoKey))
    }

    /// 只接受合法的 URL scheme（RFC 3986：字母开头，后接字母/数字/+-.）；
    /// 缺失、未展开的构建变量或非法值都回退为 `easycontext`。
    static func resolve(_ value: Any?) -> String {
        guard let raw = value as? String else { return fallback }
        let scheme = raw.lowercased()
        guard let first = scheme.unicodeScalars.first,
              CharacterSet.lowercaseLetters.contains(first),
              scheme.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+-.".unicodeScalars.contains($0)) })
        else { return fallback }
        return scheme
    }
}

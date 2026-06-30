import Foundation

public struct UniqueNameResolver {
    private let exists: (String) -> Bool

    public init(exists: @escaping (String) -> Bool) {
        self.exists = exists
    }

    /// 返回不冲突的完整文件名（含扩展名）；冲突时在基名后追加 ` 2`、` 3` …
    public func uniqueName(base: String, ext: String) -> String {
        let suffix = ext.isEmpty ? "" : "." + ext
        let first = base + suffix
        if !exists(first) { return first }
        var n = 2
        while true {
            let candidate = "\(base) \(n)\(suffix)"
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}

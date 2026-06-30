import Foundation

public struct AppDetector {
    private let isInstalled: (String) -> Bool

    public init(isInstalled: @escaping (String) -> Bool) {
        self.isInstalled = isInstalled
    }

    public func installed(from apps: [KnownApp]) -> [KnownApp] {
        apps.filter { isInstalled($0.bundleId) }
    }
}

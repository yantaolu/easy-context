import Foundation
import AppKit

/// Runtime facts for installed apps, keyed by bundle id.
/// KnownApps provides candidates and ordering; LaunchServices/the app bundle provide current facts.
public struct InstalledAppInfo: Equatable, Sendable {
    public let bundleId: String
    public let url: URL
    public let displayName: String

    public init(bundleId: String, url: URL, displayName: String) {
        self.bundleId = bundleId
        self.url = url
        self.displayName = displayName
    }
}

public struct InstalledAppSnapshot: Sendable {
    private let apps: [String: InstalledAppInfo]

    public init(apps: [String: InstalledAppInfo]) {
        self.apps = apps
    }

    public static func capture(bundleIds: Set<String>) -> InstalledAppSnapshot {
        var apps: [String: InstalledAppInfo] = [:]
        for bundleId in bundleIds {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { continue }
            apps[bundleId] = InstalledAppInfo(
                bundleId: bundleId,
                url: url,
                displayName: Self.displayName(for: url, fallback: bundleId)
            )
        }
        return InstalledAppSnapshot(apps: apps)
    }

    public func info(for bundleId: String) -> InstalledAppInfo? {
        apps[bundleId]
    }

    public func isInstalled(_ bundleId: String) -> Bool {
        apps[bundleId] != nil
    }

    public func knownApps(from candidates: [KnownApp]) -> [KnownApp] {
        candidates.compactMap { app in
            guard let info = apps[app.bundleId] else { return nil }
            return KnownApp(bundleId: app.bundleId, displayName: info.displayName, category: app.category)
        }
    }

    public func refreshedEntry(_ entry: AppEntry) -> AppEntry {
        guard let info = apps[entry.bundleId] else { return entry }
        var copy = entry
        copy.name = info.displayName
        return copy
    }

    /// 并入一条已知安装的 App（如用户刚在面板里选中的 .app）——无需 LaunchServices 查询。
    public func adding(_ info: InstalledAppInfo) -> InstalledAppSnapshot {
        var copy = apps
        copy[info.bundleId] = info
        return InstalledAppSnapshot(apps: copy)
    }

    public static func displayName(for url: URL, fallback: String) -> String {
        let fromFileManager = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        if !fromFileManager.isEmpty { return fromFileManager }
        let bundle = Bundle(url: url)
        let fromBundle = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        if let fromBundle, !fromBundle.isEmpty { return fromBundle }
        return fallback
    }
}

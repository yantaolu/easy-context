import Foundation

public enum AppCategory: String, Codable, Sendable {
    case terminal
    case editor
}

public struct KnownApp: Identifiable, Equatable, Sendable {
    public let bundleId: String
    public let displayName: String
    public let category: AppCategory

    public var id: String { bundleId }

    public init(bundleId: String, displayName: String, category: AppCategory) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.category = category
    }
}

public enum KnownApps {
    // 注意：部分 bundle id（Cursor / Trae 等）为初版猜测值，
    // 实现 Task 9/10 时应在真机用 `osascript -e 'id of app "Cursor"'` 核对后修正。
    public static let terminals: [KnownApp] = [
        KnownApp(bundleId: "com.apple.Terminal", displayName: "Terminal", category: .terminal),
        KnownApp(bundleId: "com.googlecode.iterm2", displayName: "iTerm", category: .terminal),
        KnownApp(bundleId: "dev.warp.Warp-Stable", displayName: "Warp", category: .terminal),
        KnownApp(bundleId: "com.mitchellh.ghostty", displayName: "Ghostty", category: .terminal),
        KnownApp(bundleId: "net.kovidgoyal.kitty", displayName: "kitty", category: .terminal),
        KnownApp(bundleId: "com.github.wez.wezterm", displayName: "WezTerm", category: .terminal),
        KnownApp(bundleId: "io.alacritty", displayName: "Alacritty", category: .terminal),
        KnownApp(bundleId: "co.zeit.hyper", displayName: "Hyper", category: .terminal),
    ]

    public static let editors: [KnownApp] = [
        KnownApp(bundleId: "com.microsoft.VSCode", displayName: "VSCode", category: .editor),
        KnownApp(bundleId: "com.todesktop.230313mzl4w4u92", displayName: "Cursor", category: .editor),
        KnownApp(bundleId: "com.trae.app", displayName: "Trae", category: .editor),
        KnownApp(bundleId: "com.jetbrains.WebStorm", displayName: "WebStorm", category: .editor),
        KnownApp(bundleId: "com.jetbrains.intellij", displayName: "IntelliJ IDEA", category: .editor),
        KnownApp(bundleId: "com.sublimetext.4", displayName: "Sublime Text", category: .editor),
        KnownApp(bundleId: "dev.zed.Zed", displayName: "Zed", category: .editor),
    ]

    public static let all: [KnownApp] = terminals + editors
}

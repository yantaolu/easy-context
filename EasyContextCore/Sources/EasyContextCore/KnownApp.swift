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
    public static let muxyBundleId = "com.muxy.app"

    // bundle id 来自公开资料，未装的写错也只是“不显示”，无副作用；
    // 真机已装的若没出现，用 `osascript -e 'id of app "名称"'` 核对后修正。
    public static let terminals: [KnownApp] = [
        KnownApp(bundleId: "com.apple.Terminal", displayName: "Terminal", category: .terminal),
        KnownApp(bundleId: "com.googlecode.iterm2", displayName: "iTerm", category: .terminal),
        KnownApp(bundleId: "dev.warp.Warp-Stable", displayName: "Warp", category: .terminal),
        KnownApp(bundleId: "io.appmakes.otty", displayName: "Otty", category: .terminal),
        KnownApp(bundleId: "com.mitchellh.ghostty", displayName: "Ghostty", category: .terminal),
        KnownApp(bundleId: muxyBundleId, displayName: "Muxy", category: .terminal),
        KnownApp(bundleId: "net.kovidgoyal.kitty", displayName: "kitty", category: .terminal),
        KnownApp(bundleId: "com.github.wez.wezterm", displayName: "WezTerm", category: .terminal),
        KnownApp(bundleId: "org.alacritty", displayName: "Alacritty", category: .terminal),
        KnownApp(bundleId: "co.zeit.hyper", displayName: "Hyper", category: .terminal),
        KnownApp(bundleId: "org.tabby", displayName: "Tabby", category: .terminal),
        KnownApp(bundleId: "com.raphaelamorim.rio", displayName: "Rio", category: .terminal),
        KnownApp(bundleId: "dev.commandline.waveterm", displayName: "Wave", category: .terminal),
        KnownApp(bundleId: "com.termius-dmg.mac", displayName: "Termius", category: .terminal),
    ]

    public static let editors: [KnownApp] = [
        KnownApp(bundleId: "com.microsoft.VSCode", displayName: "VS Code", category: .editor),
        KnownApp(bundleId: "com.vscodium", displayName: "VSCodium", category: .editor),
        KnownApp(bundleId: "com.todesktop.230313mzl4w4u92", displayName: "Cursor", category: .editor),
        KnownApp(bundleId: "com.trae.app", displayName: "Trae", category: .editor),
        KnownApp(bundleId: "com.exafunction.windsurf", displayName: "Devin", category: .editor),
        KnownApp(bundleId: "com.tencent.codebuddy", displayName: "CodeBuddy", category: .editor),
        KnownApp(bundleId: "dev.zed.Zed", displayName: "Zed", category: .editor),
        KnownApp(bundleId: "com.sublimetext.4", displayName: "Sublime Text", category: .editor),
        KnownApp(bundleId: "com.panic.Nova", displayName: "Nova", category: .editor),
        KnownApp(bundleId: "com.barebones.bbedit", displayName: "BBEdit", category: .editor),
        KnownApp(bundleId: "com.macromates.TextMate", displayName: "TextMate", category: .editor),
        KnownApp(bundleId: "org.vim.MacVim", displayName: "MacVim", category: .editor),
        KnownApp(bundleId: "org.gnu.Emacs", displayName: "Emacs", category: .editor),
        KnownApp(bundleId: "com.apple.dt.Xcode", displayName: "Xcode", category: .editor),
        // JetBrains 全家桶
        KnownApp(bundleId: "com.jetbrains.WebStorm", displayName: "WebStorm", category: .editor),
        KnownApp(bundleId: "com.jetbrains.intellij", displayName: "IntelliJ IDEA", category: .editor),
        KnownApp(bundleId: "com.jetbrains.intellij.ce", displayName: "IntelliJ IDEA CE", category: .editor),
        KnownApp(bundleId: "com.jetbrains.pycharm", displayName: "PyCharm", category: .editor),
        KnownApp(bundleId: "com.jetbrains.pycharm.ce", displayName: "PyCharm CE", category: .editor),
        KnownApp(bundleId: "com.jetbrains.goland", displayName: "GoLand", category: .editor),
        KnownApp(bundleId: "com.jetbrains.CLion", displayName: "CLion", category: .editor),
        KnownApp(bundleId: "com.jetbrains.PhpStorm", displayName: "PhpStorm", category: .editor),
        KnownApp(bundleId: "com.jetbrains.rubymine", displayName: "RubyMine", category: .editor),
        KnownApp(bundleId: "com.jetbrains.rider", displayName: "Rider", category: .editor),
        KnownApp(bundleId: "com.jetbrains.datagrip", displayName: "DataGrip", category: .editor),
        KnownApp(bundleId: "com.jetbrains.fleet", displayName: "Fleet", category: .editor),
        KnownApp(bundleId: "com.google.android.studio", displayName: "Android Studio", category: .editor),
    ]

    public static let all: [KnownApp] = terminals + editors
}

/// 少数 App 不接受 LaunchServices 的“用应用打开目录”文稿事件，需要改走其 Deep Link。
public enum AppOpenRouting {
    /// 返回目录的 App 专用 URL；nil 表示继续使用通用 NSWorkspace 文稿打开方式。
    public static func customDirectoryURL(for bundleId: String, directory: URL) -> URL? {
        guard bundleId == KnownApps.muxyBundleId, directory.isFileURL else { return nil }
        var components = URLComponents()
        components.scheme = "muxy"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "path", value: directory.path)]
        return components.url
    }
}

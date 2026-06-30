# Easy Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 自研一款 macOS 应用，扩展访达右键菜单：复制完整/相对路径、自动识别并打开终端与编辑器、外置磁盘支持、新建文件（模板）。

**Architecture:** 单个 Xcode 工程含三部分——SwiftUI 宿主 App（设置界面）、FinderSync 扩展（注入并响应右键菜单）、一个本地 Swift 包 `EasyContextCore`（纯逻辑，宿主与扩展共享）。配置通过 App Group 共享 `UserDefaults` 传递。所有可测逻辑下沉到 `EasyContextCore`，用命令行 `swift test` 做 TDD；访达集成与 UI 用手动验证。

**Tech Stack:** Swift 6.3 / SwiftUI / AppKit / FinderSync framework / Swift Package Manager / XCTest。

## Global Constraints

- 目标系统：macOS 13+（Package 的 `platforms: [.macOS(.v13)]`，Xcode target Deployment 设为 13.0）。
- Swift 工具链 6.3 已装，命令行 `swift build` / `swift test` 可用（阶段 A 全程用它）。
- **完整版 Xcode 是阶段 B 的硬前提**。当前机器只装了 Command Line Tools，`xcodebuild` 不可用。开始 Task 8 前必须：从 App Store 安装 Xcode，然后运行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。
- bundle id：宿主 App = `com.luyantao.easycontext`；扩展 = `com.luyantao.easycontext.finder`；App Group = `group.com.luyantao.easycontext`。
- App Sandbox：**关闭**（本地自用）。
- 配置存储：App Group 共享 `UserDefaults(suiteName: "group.com.luyantao.easycontext")`，key = `settings`，JSON 编码。
- 菜单形态：平铺列表，不用二级子菜单。
- 打开命令统一为 `/usr/bin/open -b <bundleId> <目标目录>`（v1 所有终端/编辑器一致；个别需特殊参数的留作后续）。
- 新建文件重名：自动追加 ` 2`、` 3` …（如 `未命名 2.md`）。
- 所有面向用户的 UI 文案用简体中文。
- v1 不做：菜单栏图标、公证、上架。

---

## 阶段 A — EasyContextCore 纯逻辑包（命令行 TDD，现在即可执行）

包目录位于仓库根的 `EasyContextCore/`。Xcode 工程后续以「本地 Swift 包」方式引用它。

### Task 1: 初始化 EasyContextCore 包与冒烟测试

**Files:**
- Create: `EasyContextCore/Package.swift`
- Create: `EasyContextCore/Sources/EasyContextCore/EasyContextCore.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/SmokeTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: 可构建可测试的包 `EasyContextCore`；`public func easyContextCoreVersion() -> String`

- [ ] **Step 1: 创建 Package.swift**

`EasyContextCore/Package.swift`：
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyContextCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "EasyContextCore", targets: ["EasyContextCore"]),
    ],
    targets: [
        .target(name: "EasyContextCore"),
        .testTarget(name: "EasyContextCoreTests", dependencies: ["EasyContextCore"]),
    ]
)
```

- [ ] **Step 2: 写一个会失败的冒烟测试**

`EasyContextCore/Tests/EasyContextCoreTests/SmokeTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class SmokeTests: XCTestCase {
    func test_version_isNotEmpty() {
        XCTAssertFalse(easyContextCoreVersion().isEmpty)
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run: `cd EasyContextCore && swift test`
Expected: 编译失败，`cannot find 'easyContextCoreVersion' in scope`

- [ ] **Step 4: 写最小实现**

`EasyContextCore/Sources/EasyContextCore/EasyContextCore.swift`：
```swift
import Foundation

public func easyContextCoreVersion() -> String {
    "0.1.0"
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `cd EasyContextCore && swift test`
Expected: PASS（1 test）

- [ ] **Step 6: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 初始化 EasyContextCore 包与冒烟测试"
```

---

### Task 2: TargetDirectoryResolver（取操作目录）

选中的是目录就用它本身；是文件就用其所在目录。

**Files:**
- Create: `EasyContextCore/Sources/EasyContextCore/TargetDirectoryResolver.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/TargetDirectoryResolverTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `TargetDirectoryResolver(isDirectory: @escaping (URL) -> Bool)`，`func directory(for url: URL) -> URL`；以及便捷构造 `init(fileManager: FileManager = .default)`

- [ ] **Step 1: 写失败测试**

`TargetDirectoryResolverTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class TargetDirectoryResolverTests: XCTestCase {
    func test_directory_returnsSelf_whenDirectory() {
        let dir = URL(fileURLWithPath: "/Users/me/projects")
        let sut = TargetDirectoryResolver(isDirectory: { $0 == dir })
        XCTAssertEqual(sut.directory(for: dir), dir)
    }

    func test_directory_returnsParent_whenFile() {
        let file = URL(fileURLWithPath: "/Users/me/projects/readme.md")
        let sut = TargetDirectoryResolver(isDirectory: { _ in false })
        XCTAssertEqual(sut.directory(for: file),
                       URL(fileURLWithPath: "/Users/me/projects"))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd EasyContextCore && swift test --filter TargetDirectoryResolverTests`
Expected: FAIL，`cannot find 'TargetDirectoryResolver'`

- [ ] **Step 3: 实现**

`TargetDirectoryResolver.swift`：
```swift
import Foundation

public struct TargetDirectoryResolver {
    private let isDirectory: (URL) -> Bool

    public init(isDirectory: @escaping (URL) -> Bool) {
        self.isDirectory = isDirectory
    }

    public init(fileManager: FileManager = .default) {
        self.isDirectory = { url in
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
    }

    /// 选中目录则返回自身，选中文件则返回其父目录。
    public func directory(for url: URL) -> URL {
        isDirectory(url) ? url : url.deletingLastPathComponent()
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd EasyContextCore && swift test --filter TargetDirectoryResolverTests`
Expected: PASS（2 tests）

- [ ] **Step 5: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 添加 TargetDirectoryResolver"
```

---

### Task 3: RelativePathResolver（相对 git 根的相对路径）

向上找最近含 `.git` 的祖先目录作为根；不在 git 仓库内则回退到 `~/...`；连家目录都不在则返回绝对路径。

**Files:**
- Create: `EasyContextCore/Sources/EasyContextCore/RelativePathResolver.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/RelativePathResolverTests.swift`

**Interfaces:**
- Consumes: 无
- Produces: `RelativePathResolver(directoryExists: @escaping (URL) -> Bool, homeDirectory: URL)`；`func gitRoot(for url: URL) -> URL?`；`func relativePath(for url: URL) -> String`；便捷构造 `init(fileManager: FileManager = .default)`

- [ ] **Step 1: 写失败测试**

`RelativePathResolverTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class RelativePathResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/me")

    func test_gitRoot_findsNearestAncestorWithDotGit() {
        let repo = URL(fileURLWithPath: "/Users/me/work/app")
        let sut = RelativePathResolver(
            directoryExists: { $0.path == "/Users/me/work/app/.git" },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/work/app/src/main.swift")
        XCTAssertEqual(sut.gitRoot(for: file), repo)
    }

    func test_relativePath_insideRepo_isRelativeToRoot() {
        let sut = RelativePathResolver(
            directoryExists: { $0.path == "/Users/me/work/app/.git" },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/work/app/src/main.swift")
        XCTAssertEqual(sut.relativePath(for: file), "src/main.swift")
    }

    func test_relativePath_outsideRepo_fallsBackToHome() {
        let sut = RelativePathResolver(
            directoryExists: { _ in false },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/Desktop/note.txt")
        XCTAssertEqual(sut.relativePath(for: file), "~/Desktop/note.txt")
    }

    func test_relativePath_outsideHome_returnsAbsolute() {
        let sut = RelativePathResolver(
            directoryExists: { _ in false },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Volumes/USB/data.csv")
        XCTAssertEqual(sut.relativePath(for: file), "/Volumes/USB/data.csv")
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd EasyContextCore && swift test --filter RelativePathResolverTests`
Expected: FAIL，`cannot find 'RelativePathResolver'`

- [ ] **Step 3: 实现**

`RelativePathResolver.swift`：
```swift
import Foundation

public struct RelativePathResolver {
    private let directoryExists: (URL) -> Bool
    private let homeDirectory: URL

    public init(directoryExists: @escaping (URL) -> Bool, homeDirectory: URL) {
        self.directoryExists = directoryExists
        self.homeDirectory = homeDirectory
    }

    public init(fileManager: FileManager = .default) {
        self.directoryExists = { url in
            var isDir: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
        self.homeDirectory = fileManager.homeDirectoryForCurrentUser
    }

    /// 从 url 向上（含自身目录）查找第一个含 `.git` 的祖先。
    public func gitRoot(for url: URL) -> URL? {
        var current = url.standardizedFileURL
        while true {
            if directoryExists(current.appendingPathComponent(".git")) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil } // 到文件系统根
            current = parent
        }
    }

    /// git 仓库内：相对仓库根；否则回退 `~/...`；再否则返回绝对路径。
    public func relativePath(for url: URL) -> String {
        let target = url.standardizedFileURL
        if let root = gitRoot(for: target) {
            return Self.relative(from: root, to: target)
        }
        let home = homeDirectory.standardizedFileURL
        if target.path == home.path || target.path.hasPrefix(home.path + "/") {
            return "~/" + Self.relative(from: home, to: target)
        }
        return target.path
    }

    static func relative(from base: URL, to target: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        var i = 0
        while i < baseComponents.count && i < targetComponents.count
            && baseComponents[i] == targetComponents[i] {
            i += 1
        }
        let ups = Array(repeating: "..", count: baseComponents.count - i)
        let downs = Array(targetComponents[i...])
        let parts = ups + downs
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd EasyContextCore && swift test --filter RelativePathResolverTests`
Expected: PASS（4 tests）

- [ ] **Step 5: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 添加 RelativePathResolver（相对 git 根/家目录）"
```

---

### Task 4: KnownApp 模型 + 已知清单 + AppDetector

**Files:**
- Create: `EasyContextCore/Sources/EasyContextCore/KnownApp.swift`
- Create: `EasyContextCore/Sources/EasyContextCore/AppDetector.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/AppDetectorTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum AppCategory: String, Codable, Sendable { case terminal, editor }`
  - `struct KnownApp { let bundleId: String; let displayName: String; let category: AppCategory }`，`Identifiable`（`id == bundleId`）、`Equatable`、`Sendable`
  - `enum KnownApps { static let terminals: [KnownApp]; static let editors: [KnownApp]; static let all: [KnownApp] }`
  - `struct AppDetector(isInstalled: @escaping (String) -> Bool)`，`func installed(from: [KnownApp]) -> [KnownApp]`

- [ ] **Step 1: 写失败测试**

`AppDetectorTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class AppDetectorTests: XCTestCase {
    func test_installed_filtersToInstalledBundleIds() {
        let installedSet: Set<String> = ["com.apple.Terminal", "com.microsoft.VSCode"]
        let sut = AppDetector(isInstalled: { installedSet.contains($0) })
        let result = sut.installed(from: KnownApps.all).map(\.bundleId)
        XCTAssertEqual(Set(result), installedSet)
    }

    func test_knownApps_haveUniqueBundleIds() {
        let ids = KnownApps.all.map(\.bundleId)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_knownApps_categoriesAreConsistent() {
        XCTAssertTrue(KnownApps.terminals.allSatisfy { $0.category == .terminal })
        XCTAssertTrue(KnownApps.editors.allSatisfy { $0.category == .editor })
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd EasyContextCore && swift test --filter AppDetectorTests`
Expected: FAIL，`cannot find 'AppDetector'` / `'KnownApps'`

- [ ] **Step 3: 实现 KnownApp.swift**

```swift
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
```

- [ ] **Step 4: 实现 AppDetector.swift**

```swift
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
```

- [ ] **Step 5: 运行确认通过**

Run: `cd EasyContextCore && swift test --filter AppDetectorTests`
Expected: PASS（3 tests）

- [ ] **Step 6: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 添加 KnownApp 清单与 AppDetector"
```

---

### Task 5: OpenCommand（构造 open 命令）

**Files:**
- Create: `EasyContextCore/Sources/EasyContextCore/OpenCommand.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/OpenCommandTests.swift`

**Interfaces:**
- Consumes: `KnownApp`
- Produces:
  - `struct ProcessSpec: Equatable, Sendable { let launchPath: String; let arguments: [String] }`
  - `enum OpenCommand { static func open(app: KnownApp, directory: URL) -> ProcessSpec }`

- [ ] **Step 1: 写失败测试**

`OpenCommandTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class OpenCommandTests: XCTestCase {
    func test_open_buildsOpenWithBundleIdAndDirectory() {
        let app = KnownApp(bundleId: "com.microsoft.VSCode",
                           displayName: "VSCode", category: .editor)
        let dir = URL(fileURLWithPath: "/Users/me/work/app")
        let spec = OpenCommand.open(app: app, directory: dir)
        XCTAssertEqual(spec.launchPath, "/usr/bin/open")
        XCTAssertEqual(spec.arguments,
                       ["-b", "com.microsoft.VSCode", "/Users/me/work/app"])
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd EasyContextCore && swift test --filter OpenCommandTests`
Expected: FAIL，`cannot find 'OpenCommand'`

- [ ] **Step 3: 实现**

`OpenCommand.swift`：
```swift
import Foundation

public struct ProcessSpec: Equatable, Sendable {
    public let launchPath: String
    public let arguments: [String]

    public init(launchPath: String, arguments: [String]) {
        self.launchPath = launchPath
        self.arguments = arguments
    }
}

public enum OpenCommand {
    /// 构造 `open -b <bundleId> <dir>`：用目标目录打开该 App
    /// （编辑器视为项目目录、终端视为工作目录）。
    public static func open(app: KnownApp, directory: URL) -> ProcessSpec {
        ProcessSpec(launchPath: "/usr/bin/open",
                    arguments: ["-b", app.bundleId, directory.path])
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `cd EasyContextCore && swift test --filter OpenCommandTests`
Expected: PASS（1 test）

- [ ] **Step 5: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 添加 OpenCommand 构造器"
```

---

### Task 6: FileTemplate + UniqueNameResolver（新建文件逻辑）

**Files:**
- Create: `EasyContextCore/Sources/EasyContextCore/FileTemplate.swift`
- Create: `EasyContextCore/Sources/EasyContextCore/UniqueNameResolver.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/FileTemplateTests.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/UniqueNameResolverTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum FileTemplate: String, CaseIterable, Codable, Sendable { case blank, markdown, text, shell, json }`，属性 `fileExtension: String`、`initialContent: String`、`isExecutable: Bool`、`displayName: String`
  - `struct UniqueNameResolver(exists: @escaping (String) -> Bool)`，`func uniqueName(base: String, ext: String) -> String`

- [ ] **Step 1: 写失败测试（FileTemplate）**

`FileTemplateTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class FileTemplateTests: XCTestCase {
    func test_shell_hasShebangAndIsExecutable() {
        XCTAssertEqual(FileTemplate.shell.fileExtension, "sh")
        XCTAssertEqual(FileTemplate.shell.initialContent, "#!/bin/bash\n")
        XCTAssertTrue(FileTemplate.shell.isExecutable)
    }

    func test_json_hasEmptyObject() {
        XCTAssertEqual(FileTemplate.json.fileExtension, "json")
        XCTAssertEqual(FileTemplate.json.initialContent, "{}\n")
        XCTAssertFalse(FileTemplate.json.isExecutable)
    }

    func test_blank_hasNoExtensionNoContent() {
        XCTAssertEqual(FileTemplate.blank.fileExtension, "")
        XCTAssertEqual(FileTemplate.blank.initialContent, "")
    }
}
```

- [ ] **Step 2: 写失败测试（UniqueNameResolver）**

`UniqueNameResolverTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class UniqueNameResolverTests: XCTestCase {
    func test_uniqueName_returnsBase_whenFree() {
        let sut = UniqueNameResolver(exists: { _ in false })
        XCTAssertEqual(sut.uniqueName(base: "未命名", ext: "md"), "未命名.md")
    }

    func test_uniqueName_appendsCounter_whenTaken() {
        let taken: Set<String> = ["未命名.md", "未命名 2.md"]
        let sut = UniqueNameResolver(exists: { taken.contains($0) })
        XCTAssertEqual(sut.uniqueName(base: "未命名", ext: "md"), "未命名 3.md")
    }

    func test_uniqueName_handlesEmptyExtension() {
        let taken: Set<String> = ["未命名"]
        let sut = UniqueNameResolver(exists: { taken.contains($0) })
        XCTAssertEqual(sut.uniqueName(base: "未命名", ext: ""), "未命名 2")
    }
}
```

- [ ] **Step 3: 运行确认失败**

Run: `cd EasyContextCore && swift test --filter FileTemplateTests`
Expected: FAIL，`cannot find 'FileTemplate'`

- [ ] **Step 4: 实现 FileTemplate.swift**

```swift
import Foundation

public enum FileTemplate: String, CaseIterable, Codable, Sendable {
    case blank
    case markdown
    case text
    case shell
    case json

    public var fileExtension: String {
        switch self {
        case .blank: return ""
        case .markdown: return "md"
        case .text: return "txt"
        case .shell: return "sh"
        case .json: return "json"
        }
    }

    public var initialContent: String {
        switch self {
        case .blank, .text, .markdown: return ""
        case .shell: return "#!/bin/bash\n"
        case .json: return "{}\n"
        }
    }

    public var isExecutable: Bool {
        self == .shell
    }

    public var displayName: String {
        switch self {
        case .blank: return "空白文件"
        case .markdown: return "Markdown (.md)"
        case .text: return "文本 (.txt)"
        case .shell: return "Shell (.sh)"
        case .json: return "JSON (.json)"
        }
    }
}
```

- [ ] **Step 5: 实现 UniqueNameResolver.swift**

```swift
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
```

- [ ] **Step 6: 运行全部新测试确认通过**

Run: `cd EasyContextCore && swift test --filter FileTemplateTests && swift test --filter UniqueNameResolverTests`
Expected: 两组均 PASS（3 + 3 tests）

- [ ] **Step 7: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 添加 FileTemplate 与 UniqueNameResolver"
```

---

### Task 7: Settings（共享配置读写）

**Files:**
- Create: `EasyContextCore/Sources/EasyContextCore/Settings.swift`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/SettingsTests.swift`

**Interfaces:**
- Consumes: `FileTemplate`
- Produces:
  - `struct Settings: Codable, Equatable, Sendable`，字段：`copyFullPathEnabled: Bool`、`copyRelativePathEnabled: Bool`、`newFileEnabled: Bool`、`enabledTerminalBundleIds: [String]`、`enabledEditorBundleIds: [String]`、`defaultTemplate: FileTemplate`
  - `static let appGroupId = "group.com.luyantao.easycontext"`
  - `static func load(from defaults: UserDefaults) -> Settings`（无数据时返回默认值）
  - `func save(to defaults: UserDefaults)`

- [ ] **Step 1: 写失败测试**

`SettingsTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class SettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "test.easycontext.settings"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_load_returnsDefaults_whenEmpty() {
        let d = makeDefaults()
        let s = Settings.load(from: d)
        XCTAssertTrue(s.copyFullPathEnabled)
        XCTAssertTrue(s.copyRelativePathEnabled)
        XCTAssertTrue(s.newFileEnabled)
        XCTAssertEqual(s.defaultTemplate, .blank)
        XCTAssertEqual(s.enabledTerminalBundleIds, [])
    }

    func test_saveThenLoad_roundTrips() {
        let d = makeDefaults()
        var s = Settings()
        s.enabledTerminalBundleIds = ["com.googlecode.iterm2"]
        s.enabledEditorBundleIds = ["com.microsoft.VSCode"]
        s.defaultTemplate = .markdown
        s.copyFullPathEnabled = false
        s.save(to: d)

        let loaded = Settings.load(from: d)
        XCTAssertEqual(loaded, s)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `cd EasyContextCore && swift test --filter SettingsTests`
Expected: FAIL，`cannot find 'Settings'`

- [ ] **Step 3: 实现**

`Settings.swift`：
```swift
import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var copyFullPathEnabled: Bool
    public var copyRelativePathEnabled: Bool
    public var newFileEnabled: Bool
    public var enabledTerminalBundleIds: [String]
    public var enabledEditorBundleIds: [String]
    public var defaultTemplate: FileTemplate

    public init(
        copyFullPathEnabled: Bool = true,
        copyRelativePathEnabled: Bool = true,
        newFileEnabled: Bool = true,
        enabledTerminalBundleIds: [String] = [],
        enabledEditorBundleIds: [String] = [],
        defaultTemplate: FileTemplate = .blank
    ) {
        self.copyFullPathEnabled = copyFullPathEnabled
        self.copyRelativePathEnabled = copyRelativePathEnabled
        self.newFileEnabled = newFileEnabled
        self.enabledTerminalBundleIds = enabledTerminalBundleIds
        self.enabledEditorBundleIds = enabledEditorBundleIds
        self.defaultTemplate = defaultTemplate
    }

    public static let appGroupId = "group.com.luyantao.easycontext"
    private static let storageKey = "settings"

    public static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 4: 运行确认通过 + 全量回归**

Run: `cd EasyContextCore && swift test`
Expected: 全部 PASS（含此前所有任务的测试）

- [ ] **Step 5: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 添加 Settings 共享配置读写"
```

---

## 阶段 B — Xcode 宿主 App + FinderSync 扩展（需完整 Xcode，手动验证）

> 开始前确认：已安装 Xcode 且 `xcodebuild -version` 正常输出（见 Global Constraints）。
> 本阶段无法用 `swift test` 自动化（访达 UI / 系统扩展），各任务以「明确操作步骤 + 预期结果」做手动验证。

### Task 8: 创建 Xcode 工程（宿主 App + 扩展 + 接入 Core 包）

**Files:**
- Create: `EasyContext.xcodeproj`（Xcode 生成）
- Create: `EasyContext/`（宿主 App target 源目录）
- Create: `EasyContextFinder/`（扩展 target 源目录）
- Modify: 两个 target 的 entitlements 与 Info.plist

**Interfaces:**
- Consumes: 本地包 `EasyContextCore`
- Produces: 可编译运行的空壳宿主 App + 已注册的 FinderSync 扩展

- [ ] **Step 1: 新建 App 工程**

Xcode → File → New → Project → macOS → App。
- Product Name: `EasyContext`
- Organization Identifier: `com.luyantao`（使 bundle id = `com.luyantao.easycontext`）
- Interface: SwiftUI，Language: Swift。
- 保存到仓库根 `/Volumes/Samsung/codes/easy-context/`（与 `EasyContextCore/`、`docs/` 同级）。

- [ ] **Step 2: 添加 FinderSync 扩展 target**

File → New → Target → macOS → Finder Sync Extension。
- Product Name: `EasyContextFinder`（bundle id 自动成为 `com.luyantao.easycontext.finder`）。
- 弹窗询问是否 activate scheme：Activate。

- [ ] **Step 3: 关闭沙盒、配置 App Group（两个 target 都做）**

对 `EasyContext` 与 `EasyContextFinder` 两个 target：
- Signing & Capabilities → 若存在 `App Sandbox` 能力则删除（本地自用关闭沙盒）。
- 添加 Capability → App Groups → 勾选/新增 `group.com.luyantao.easycontext`。
- Signing：Team 选你的个人账号或 “Sign to Run Locally”。

- [ ] **Step 4: 接入本地 Core 包**

File → Add Package Dependencies → Add Local → 选择仓库内 `EasyContextCore` 目录。
- 在 `EasyContext` 与 `EasyContextFinder` 两个 target 的 “Frameworks, Libraries” 里都加上 `EasyContextCore` 库产物。

- [ ] **Step 5: 编译验证**

Run: `xcodebuild -scheme EasyContext -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 手动验证扩展能注册**

运行 App（Cmd+R）→ 打开「系统设置 → 通用 → 登录项与扩展 → 访达扩展」→ 勾选 `EasyContextFinder`。
Expected: 列表中能看到并启用该扩展，无报错。

- [ ] **Step 7: 提交**

```bash
git add -A
git commit -m "feat(app): 创建宿主 App 与 FinderSync 扩展工程并接入 Core"
```

---

### Task 9: FinderSync 扩展——菜单注入与动作（复制路径 / 打开终端 / 打开编辑器）

**Files:**
- Modify: `EasyContextFinder/FinderSync.swift`（替换 Xcode 模板生成的主类）

**Interfaces:**
- Consumes: `EasyContextCore`（`Settings`、`KnownApps`、`AppDetector`、`OpenCommand`、`TargetDirectoryResolver`、`RelativePathResolver`、`ProcessSpec`）
- Produces: 右键菜单注入 + 动作执行；私有 selector `copyFullPath:`、`copyRelativePath:`、`openWithApp:`（后者经 `representedObject` 带 bundleId）

- [ ] **Step 1: 实现扩展主类**

`EasyContextFinder/FinderSync.swift`（整文件替换）：
```swift
import Cocoa
import FinderSync
import EasyContextCore

class FinderSync: FIFinderSync {
    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: Settings.appGroupId) ?? .standard
    }

    override init() {
        super.init()
        // 监控根目录，使内置盘与所有外置磁盘（/Volumes/*）均生效。
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - 目标 URL

    private func targetURLs() -> [URL] {
        let controller = FIFinderSyncController.default()
        if let items = controller.selectedItemURLs(), !items.isEmpty {
            return items
        }
        if let target = controller.targetedURL() {
            return [target]
        }
        return []
    }

    private func primaryURL() -> URL? { targetURLs().first }

    private func targetDirectory() -> URL? {
        guard let url = primaryURL() else { return nil }
        return TargetDirectoryResolver().directory(for: url)
    }

    // MARK: - 菜单构建

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems
                || menuKind == .contextualMenuForContainer else { return nil }
        guard primaryURL() != nil else { return nil }

        let settings = Settings.load(from: sharedDefaults)
        let menu = NSMenu(title: "")

        if settings.copyFullPathEnabled {
            addItem(to: menu, title: "复制完整路径",
                    action: #selector(copyFullPath(_:)))
        }
        if settings.copyRelativePathEnabled {
            addItem(to: menu, title: "复制相对路径",
                    action: #selector(copyRelativePath(_:)))
        }

        let detector = AppDetector(isInstalled: Self.isInstalled)
        let terminals = detector.installed(from: KnownApps.terminals)
            .filter { settings.enabledTerminalBundleIds.contains($0.bundleId) }
        let editors = detector.installed(from: KnownApps.editors)
            .filter { settings.enabledEditorBundleIds.contains($0.bundleId) }

        if !terminals.isEmpty || !editors.isEmpty { menu.addItem(.separator()) }
        for app in terminals {
            let item = addItem(to: menu, title: "用 \(app.displayName) 打开终端",
                               action: #selector(openWithApp(_:)))
            item.representedObject = app.bundleId
        }
        for app in editors {
            let item = addItem(to: menu, title: "用 \(app.displayName) 打开",
                               action: #selector(openWithApp(_:)))
            item.representedObject = app.bundleId
        }

        if settings.newFileEnabled {
            menu.addItem(.separator())
            addItem(to: menu, title: "新建文件…",
                    action: #selector(newFile(_:)))
        }
        return menu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    static func isInstalled(_ bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    // MARK: - 动作

    @objc private func copyFullPath(_ sender: AnyObject?) {
        guard let url = primaryURL() else { return }
        writeToPasteboard(url.path)
    }

    @objc private func copyRelativePath(_ sender: AnyObject?) {
        guard let url = primaryURL() else { return }
        let rel = RelativePathResolver().relativePath(for: url)
        writeToPasteboard(rel)
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String,
              let dir = targetDirectory(),
              let app = KnownApps.all.first(where: { $0.bundleId == bundleId })
        else { return }
        run(OpenCommand.open(app: app, directory: dir))
    }

    @objc private func newFile(_ sender: AnyObject?) {
        // 在 Task 11 实现
        NewFileController(defaults: sharedDefaults).run(in: targetDirectory())
    }

    private func writeToPasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private func run(_ spec: ProcessSpec) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: spec.launchPath)
        process.arguments = spec.arguments
        do { try process.run() }
        catch { NSLog("EasyContext open failed: \(error)") }
    }
}
```

> 注：`newFile(_:)` 依赖 Task 11 的 `NewFileController`。在 Task 11 完成前，先把 `newFile` 方法体临时改成 `NSLog("newFile pending")`，使本任务可独立编译验证。

- [ ] **Step 2: 临时桩使本任务可编译**

把 `newFile(_:)` 方法体临时替换为：
```swift
    @objc private func newFile(_ sender: AnyObject?) {
        NSLog("newFile pending")
    }
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -scheme EasyContext -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动核对 bundle id**

对你机器上实际安装的终端/编辑器，逐个运行核对，修正 `KnownApp.swift` 中不符的值：
Run: `osascript -e 'id of app "Cursor"'`（对 Trae、Warp、Ghostty 等同理）
Expected: 输出的 bundle id 与清单一致；不一致则更新清单并重新提交 Core。

- [ ] **Step 5: 手动验证菜单与动作**

先临时在共享配置写入启用项（可在 Task 10 设置界面完成；此处为提前验证，可在宿主 App 里加一行测试代码或用 `defaults` 命令写入），然后在访达里右键一个目录：
- 出现「复制完整路径」「复制相对路径」→ 点击后到别处 Cmd+V，核对粘贴内容正确。
- 出现「用 VSCode 打开」等 → 点击后对应编辑器/终端在该目录打开。
- 右键 git 仓库内的文件，「复制相对路径」粘贴出的是相对仓库根的路径。
- 右键非 git 目录下家目录内文件，粘贴出的是 `~/...`。

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat(finder): 注入复制路径与打开终端/编辑器菜单及动作"
```

---

### Task 10: 宿主 App 设置界面（SwiftUI）

**Files:**
- Modify: `EasyContext/ContentView.swift`（替换为设置界面）
- Create: `EasyContext/SettingsStore.swift`

**Interfaces:**
- Consumes: `EasyContextCore`（`Settings`、`KnownApps`、`AppDetector`、`FileTemplate`）
- Produces: 读写共享配置的设置界面；`final class SettingsStore: ObservableObject`，发布 `@Published var settings: Settings`，方法 `load()`、`persist()`、`detectedTerminals/detectedEditors: [KnownApp]`

- [ ] **Step 1: 实现 SettingsStore**

`EasyContext/SettingsStore.swift`：
```swift
import Foundation
import AppKit
import EasyContextCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings

    private let defaults: UserDefaults

    init() {
        self.defaults = UserDefaults(suiteName: Settings.appGroupId) ?? .standard
        self.settings = Settings.load(from: defaults)
        seedEnabledIfFirstRun()
    }

    private var detector: AppDetector {
        AppDetector(isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    var detectedTerminals: [KnownApp] { detector.installed(from: KnownApps.terminals) }
    var detectedEditors: [KnownApp] { detector.installed(from: KnownApps.editors) }

    /// 首次运行：默认勾选所有已检测到的 App。
    private func seedEnabledIfFirstRun() {
        if !Settings.hasStored(in: defaults) {
            settings.enabledTerminalBundleIds = detectedTerminals.map(\.bundleId)
            settings.enabledEditorBundleIds = detectedEditors.map(\.bundleId)
            persist()
        }
    }

    func persist() {
        settings.save(to: defaults)
    }

    func isEnabled(_ app: KnownApp) -> Bool {
        switch app.category {
        case .terminal: return settings.enabledTerminalBundleIds.contains(app.bundleId)
        case .editor: return settings.enabledEditorBundleIds.contains(app.bundleId)
        }
    }

    func toggle(_ app: KnownApp, on: Bool) {
        func update(_ ids: inout [String]) {
            if on { if !ids.contains(app.bundleId) { ids.append(app.bundleId) } }
            else { ids.removeAll { $0 == app.bundleId } }
        }
        switch app.category {
        case .terminal: update(&settings.enabledTerminalBundleIds)
        case .editor: update(&settings.enabledEditorBundleIds)
        }
        persist()
    }
}
```

- [ ] **Step 2: 实现设置界面**

`EasyContext/ContentView.swift`（整文件替换）：
```swift
import SwiftUI
import EasyContextCore

struct ContentView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        Form {
            Section("菜单项") {
                Toggle("复制完整路径", isOn: Binding(
                    get: { store.settings.copyFullPathEnabled },
                    set: { store.settings.copyFullPathEnabled = $0; store.persist() }))
                Toggle("复制相对路径（相对 git 根）", isOn: Binding(
                    get: { store.settings.copyRelativePathEnabled },
                    set: { store.settings.copyRelativePathEnabled = $0; store.persist() }))
                Toggle("新建文件", isOn: Binding(
                    get: { store.settings.newFileEnabled },
                    set: { store.settings.newFileEnabled = $0; store.persist() }))
            }

            Section("终端") {
                ForEach(store.detectedTerminals) { app in
                    appToggle(app)
                }
                if store.detectedTerminals.isEmpty { Text("未检测到终端").foregroundStyle(.secondary) }
            }

            Section("编辑器") {
                ForEach(store.detectedEditors) { app in
                    appToggle(app)
                }
                if store.detectedEditors.isEmpty { Text("未检测到编辑器").foregroundStyle(.secondary) }
            }

            Section("新建文件默认模板") {
                Picker("模板", selection: Binding(
                    get: { store.settings.defaultTemplate },
                    set: { store.settings.defaultTemplate = $0; store.persist() })) {
                    ForEach(FileTemplate.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
            }

            Section {
                Button("打开「访达扩展」设置…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("首次使用需在此勾选启用 EasyContextFinder 扩展。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    private func appToggle(_ app: KnownApp) -> some View {
        Toggle(app.displayName, isOn: Binding(
            get: { store.isEnabled(app) },
            set: { store.toggle(app, on: $0) }))
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -scheme EasyContext -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动验证设置联动**

运行 App：
- 终端/编辑器列表只显示真实安装的。
- 勾选/取消某项后，去访达右键 → 该项在菜单中相应出现/消失（扩展读的是同一份共享配置）。
- 关闭「复制相对路径」→ 菜单中该项消失。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(app): 设置界面读写共享配置、检测已装 App"
```

---

### Task 11: 新建文件动作（输入文件名 + 模板，重名加序号）

**Files:**
- Create: `EasyContextFinder/NewFileController.swift`
- Modify: `EasyContextFinder/FinderSync.swift`（移除 Task 9 的临时桩，恢复调用 `NewFileController`）

**Interfaces:**
- Consumes: `EasyContextCore`（`Settings`、`FileTemplate`、`UniqueNameResolver`）
- Produces: `struct NewFileController(defaults: UserDefaults)`，`func run(in directory: URL?)`

- [ ] **Step 1: 实现 NewFileController**

`EasyContextFinder/NewFileController.swift`：
```swift
import AppKit
import EasyContextCore

struct NewFileController {
    let defaults: UserDefaults

    func run(in directory: URL?) {
        guard let directory else { return }
        let settings = Settings.load(from: defaults)

        let alert = NSAlert()
        alert.messageText = "新建文件"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 28, width: 240, height: 24))
        field.stringValue = "未命名"

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        for t in FileTemplate.allCases { popup.addItem(withTitle: t.displayName) }
        if let idx = FileTemplate.allCases.firstIndex(of: settings.defaultTemplate) {
            popup.selectItem(at: idx)
        }

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        accessory.addSubview(field)
        accessory.addSubview(popup)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let template = FileTemplate.allCases[popup.indexOfSelectedItem]
        let base = field.stringValue.isEmpty ? "未命名" : field.stringValue
        create(base: base, template: template, in: directory)
    }

    private func create(base: String, template: FileTemplate, in directory: URL) {
        let fm = FileManager.default
        let resolver = UniqueNameResolver(exists: { name in
            fm.fileExists(atPath: directory.appendingPathComponent(name).path)
        })
        let name = resolver.uniqueName(base: base, ext: template.fileExtension)
        let fileURL = directory.appendingPathComponent(name)

        do {
            try template.initialContent.write(to: fileURL, atomically: true, encoding: .utf8)
            if template.isExecutable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
            }
        } catch {
            NSLog("EasyContext newFile failed: \(error)")
        }
    }
}
```

- [ ] **Step 2: 恢复 FinderSync 中的真实调用**

把 Task 9 里临时的 `newFile(_:)` 桩改回：
```swift
    @objc private func newFile(_ sender: AnyObject?) {
        NewFileController(defaults: sharedDefaults).run(in: targetDirectory())
    }
```

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -scheme EasyContext -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动验证新建文件**

访达右键一个目录 → 「新建文件…」：
- 弹出输入框（文件名默认「未命名」+ 模板下拉）。
- 选 Shell (.sh) 创建 → 目录出现 `未命名.sh`，内容含 `#!/bin/bash`，且 `ls -l` 显示可执行位 `-rwxr-xr-x`。
- 再次同名创建 → 得到 `未命名 2.sh`，原文件不被覆盖。
- 若弹框在扩展上下文中无法显示（系统限制），记录现象，回退方案：直接用「默认模板 + 未命名」创建并跳过弹框（在 `run` 中加 `#if` 开关），保证功能可用。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "feat(finder): 新建文件（模板 + 重名加序号）"
```

---

### Task 12: 端到端与外置磁盘验证

**Files:**
- 无新增；整体回归。

**Interfaces:**
- Consumes: 全部已实现功能
- Produces: 一次完整手动验收记录

- [ ] **Step 1: Core 全量自动回归**

Run: `cd EasyContextCore && swift test`
Expected: 全部 PASS。

- [ ] **Step 2: 整工程编译**

Run: `xcodebuild -scheme EasyContext -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 外置磁盘验证**

插入 U 盘/移动硬盘（挂载于 `/Volumes/<名称>`）：
- 在该盘内右键目录 → Easy Context 菜单项正常出现。
- 「复制完整路径」粘贴出 `/Volumes/...` 完整路径。
- 「用 VSCode 打开」能在该外置目录打开编辑器。
- 「新建文件…」能在外置盘创建成功。

- [ ] **Step 4: 核心场景清单逐项过**

逐项确认并记录结果：复制完整路径、复制相对路径（git 内/外）、各终端打开、各编辑器打开、新建文件（各模板、重名）、文件 vs 目录两种右键起点、设置开关联动。

- [ ] **Step 5: 提交验收记录（可选）**

```bash
git add -A
git commit -m "test: 端到端与外置磁盘手动验收通过"
```

---

## Self-Review 记录

- **Spec 覆盖**：复制完整路径(T9)、复制相对路径/git根回退(T3+T9)、打开终端自动识别(T4+T9+T10)、打开编辑器(T4+T9+T10)、外置磁盘(T9 监控根 `/` + T12 验证)、新建文件模板+重名加序号(T6+T11)、自动检测(T4+T10)、共享配置(T7+T10)、bundle id/沙盒关闭/macOS13(Global Constraints + T8) — 均有对应任务。
- **占位符**：阶段 A 全部含完整代码与可运行命令；阶段 B 含完整源文件，验证为手动步骤（访达 UI 无法自动化，属合理）。无 TBD/TODO 残留（T9→T11 的临时桩有明确恢复步骤）。
- **类型一致性**：`ProcessSpec`、`KnownApp`、`Settings`、`FileTemplate`、`AppDetector.installed(from:)`、`OpenCommand.open(app:directory:)`、`RelativePathResolver.relativePath(for:)`、`UniqueNameResolver.uniqueName(base:ext:)` 在定义任务与消费任务（T9/T10/T11）间签名一致。
- **已知风险**：(1) 部分 bundle id 为猜测值 → T9 Step 4 真机核对；(2) 扩展内 `NSAlert` 能否弹出存在系统限制 → T11 Step 4 给出回退方案。

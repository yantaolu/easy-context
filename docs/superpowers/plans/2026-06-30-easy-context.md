# Easy Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 自研一款 macOS 应用，扩展访达右键菜单：复制完整/相对路径、自动识别并打开终端与编辑器、外置磁盘支持、新建文件（模板）。

**Architecture:** 单个 Xcode 工程含三部分——SwiftUI 宿主 App（设置界面）、FinderSync 扩展（注入并响应右键菜单）、一个本地 Swift 包 `EasyContextCore`（纯逻辑，宿主与扩展共享）。配置通过共享 JSON 文件 `~/Library/Application Support/EasyContext/settings.json` 传递（沙盒已关，两进程直接读写，无需 App Group）。所有可测逻辑下沉到 `EasyContextCore`，用命令行 `swift test` 做 TDD；访达集成与 UI 用手动验证；Xcode 工程由 XcodeGen 从 `project.yml` 生成。

**Tech Stack:** Swift 6.3 / SwiftUI / AppKit / FinderSync framework / Swift Package Manager / XcodeGen / XCTest。

## Global Constraints

- 目标系统：macOS 13+（Package 的 `platforms: [.macOS(.v13)]`，Xcode target Deployment 设为 13.0）。
- Swift 工具链 6.3 已装，命令行 `swift build` / `swift test` 可用（阶段 A 全程用它）。
- 完整版 Xcode 已安装（Xcode 26.6，`xcodebuild` 可用，active developer dir 指向 `/Applications/Xcode.app`）。Task 8 仍只用 `swift test`；Task 9 起需要 Xcode 与 XcodeGen（`brew install xcodegen`）。
- bundle id：宿主 App = `com.luyantao.easycontext`；扩展 = `com.luyantao.easycontext.finder`。
- App Sandbox：**关闭**（本地自用）。
- 签名：ad-hoc（`CODE_SIGN_IDENTITY = "-"`），本机无签名身份/无开发者团队，本地自用足够。
- 配置存储：共享 JSON 文件 `~/Library/Application Support/EasyContext/settings.json`，由 `ConfigStore` 读写（沙盒关闭，两进程直接访问，无需 App Group entitlement）。
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

## 阶段 B — 文件存储 + Xcode 宿主 App + FinderSync 扩展

> 架构调整（基于本机实测：0 签名身份、无开发者团队）：
> - 共享配置 **不用 App Group**，改用普通 JSON 文件 `~/Library/Application Support/EasyContext/settings.json`。沙盒已关，两进程直接读写，零 entitlement。
> - 工程用 **XcodeGen** 从版本化的 `project.yml` 生成（`brew install xcodegen`），便于脚本化与复现。
> - 签名用 **ad-hoc（`CODE_SIGN_IDENTITY = "-"`）**，本地自用即可，无需账号。
> - Task 8 仍可用 `swift test` 自动化（纯文件 IO）；Task 9 起涉及访达 UI / 系统扩展，以「明确操作步骤 + 预期结果」手动验证。

### Task 8: ConfigStore（文件存储共享配置）+ 精简 Settings

把配置持久化从 UserDefaults/App Group 迁到文件。`Settings` 退化为纯 Codable 模型；新增 `ConfigStore` 负责文件读写。可命令行 TDD。

**Files:**
- Modify: `EasyContextCore/Sources/EasyContextCore/Settings.swift`（移除 UserDefaults 持久化）
- Create: `EasyContextCore/Sources/EasyContextCore/ConfigStore.swift`
- Modify: `EasyContextCore/Tests/EasyContextCoreTests/SettingsTests.swift`（精简为模型默认值测试）
- Test: `EasyContextCore/Tests/EasyContextCoreTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `Settings`、`FileTemplate`
- Produces:
  - `Settings` 仍为 `Codable, Equatable, Sendable` 的纯模型，保留全部字段与默认值；**移除** `appGroupId`、`storageKey`、`load(from:)`、`save(to:)`。
  - `struct ConfigStore`，`init(fileURL: URL)` 与便捷 `init(fileManager: FileManager = .default)`（默认指向 `~/Library/Application Support/EasyContext/settings.json`）；`func hasStored() -> Bool`；`func load() -> Settings`（缺失/损坏返回默认）；`func save(_ settings: Settings) throws`（自动建目录、原子写）。

- [ ] **Step 1: 改写 SettingsTests（先让其失败/不编译以驱动重构）**

把 `SettingsTests.swift` 整文件替换为仅测模型默认值：
```swift
import XCTest
@testable import EasyContextCore

final class SettingsTests: XCTestCase {
    func test_defaultInit_hasExpectedDefaults() {
        let s = Settings()
        XCTAssertTrue(s.copyFullPathEnabled)
        XCTAssertTrue(s.copyRelativePathEnabled)
        XCTAssertTrue(s.newFileEnabled)
        XCTAssertEqual(s.defaultTemplate, .blank)
        XCTAssertEqual(s.enabledTerminalBundleIds, [])
        XCTAssertEqual(s.enabledEditorBundleIds, [])
    }
}
```

- [ ] **Step 2: 写 ConfigStore 失败测试**

`ConfigStoreTests.swift`：
```swift
import XCTest
@testable import EasyContextCore

final class ConfigStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("easycontext-test-\(ProcessInfo.processInfo.globallyUniqueString)")
            .appendingPathComponent("settings.json")
    }

    func test_load_returnsDefaults_whenFileMissing() {
        let sut = ConfigStore(fileURL: tempFileURL())
        XCTAssertFalse(sut.hasStored())
        XCTAssertEqual(sut.load(), Settings())
    }

    func test_saveThenLoad_roundTrips() throws {
        let sut = ConfigStore(fileURL: tempFileURL())
        var s = Settings()
        s.enabledEditorBundleIds = ["com.microsoft.VSCode"]
        s.enabledTerminalBundleIds = ["com.googlecode.iterm2"]
        s.defaultTemplate = .markdown
        s.copyFullPathEnabled = false
        try sut.save(s)
        XCTAssertTrue(sut.hasStored())
        XCTAssertEqual(sut.load(), s)
    }

    func test_load_returnsDefaults_whenCorrupt() throws {
        let url = tempFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let sut = ConfigStore(fileURL: url)
        XCTAssertEqual(sut.load(), Settings())
    }
}
```

- [ ] **Step 3: 运行确认失败**

Run: `cd EasyContextCore && swift test --filter ConfigStoreTests`
Expected: FAIL，`cannot find 'ConfigStore'`

- [ ] **Step 4: 精简 Settings.swift**

把 `Settings.swift` 中的 `appGroupId`、`storageKey`、`load(from:)`、`save(to:)` 全部删除，仅保留结构体、字段、`init`、协议遵循。结果应为：
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
}
```

- [ ] **Step 5: 实现 ConfigStore.swift**

```swift
import Foundation

public struct ConfigStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 默认指向 ~/Library/Application Support/EasyContext/settings.json
    public init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("EasyContext/settings.json")
    }

    public func hasStored() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return decoded
    }

    public func save(_ settings: Settings) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 6: 运行确认通过 + 全量回归**

Run: `cd EasyContextCore && swift test`
Expected: 全部 PASS（ConfigStore 3 + 其余无回归）。

- [ ] **Step 7: 提交**

```bash
git add EasyContextCore
git commit -m "feat(core): 用 ConfigStore 文件存储替代 UserDefaults/App Group 共享配置"
```

---

### Task 9: 用 XcodeGen 生成工程（宿主 App + FinderSync 扩展，ad-hoc 签名）

**Files:**
- Create: `project.yml`（XcodeGen 工程定义，仓库根）
- Create: `EasyContext/EasyContextApp.swift`、`EasyContext/ContentView.swift`、`EasyContext/Info.plist`（宿主 App 占位）
- Create: `EasyContextFinder/FinderSyncExtension.swift`、`EasyContextFinder/Info.plist`（扩展占位）
- Generate: `EasyContext.xcodeproj`（由 `xcodegen` 生成，不手写）

**Interfaces:**
- Consumes: 本地包 `EasyContextCore`
- Produces: 可编译运行的空壳宿主 App + 注册到访达的 FinderSync 扩展；扩展主类 `EasyContextFinder.FinderSyncExtension`

- [ ] **Step 1: 安装 XcodeGen**

Run: `brew install xcodegen && xcodegen --version`
Expected: 输出版本号（如 `Version: 2.x`）。

- [ ] **Step 2: 写 project.yml**

仓库根 `project.yml`：
```yaml
name: EasyContext
options:
  bundleIdPrefix: com.luyantao.easycontext
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
settings:
  base:
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    DEVELOPMENT_TEAM: ""
    ENABLE_HARDENED_RUNTIME: "NO"
    PRODUCT_NAME: "$(TARGET_NAME)"
    SWIFT_VERSION: "5.0"
packages:
  EasyContextCore:
    path: EasyContextCore
targets:
  EasyContext:
    type: application
    platform: macOS
    sources:
      - EasyContext
    dependencies:
      - package: EasyContextCore
        product: EasyContextCore
      - target: EasyContextFinder
        embed: true
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.luyantao.easycontext
    info:
      path: EasyContext/Info.plist
      properties:
        CFBundleDisplayName: Easy Context
        LSMinimumSystemVersion: "13.0"
        LSUIElement: false
  EasyContextFinder:
    type: app-extension
    platform: macOS
    sources:
      - EasyContextFinder
    dependencies:
      - package: EasyContextCore
        product: EasyContextCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.luyantao.easycontext.finder
    info:
      path: EasyContextFinder/Info.plist
      properties:
        CFBundleDisplayName: EasyContextFinder
        NSExtension:
          NSExtensionPointIdentifier: com.apple.FinderSync
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).FinderSyncExtension
```

> 不写 entitlements 文件：无沙盒、无 App Group，ad-hoc 签名不需要 entitlements。

- [ ] **Step 3: 写宿主 App 占位源码**

`EasyContext/EasyContextApp.swift`：
```swift
import SwiftUI

@main
struct EasyContextApp: App {
    var body: some Scene {
        Window("Easy Context", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
```

`EasyContext/ContentView.swift`（占位，Task 11 替换为设置界面）：
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Easy Context")
            .frame(width: 460, height: 560)
    }
}
```

`EasyContext/Info.plist`：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

- [ ] **Step 4: 写扩展占位源码**

`EasyContextFinder/FinderSyncExtension.swift`（占位，Task 10 实现菜单逻辑）：
```swift
import Cocoa
import FinderSync

class FinderSyncExtension: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }
}
```

`EasyContextFinder/Info.plist`：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```
> NSExtension 字典由 project.yml 注入到生成的 Info.plist，无需在此重复。

- [ ] **Step 5: 生成工程并编译**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
```
Expected: `** BUILD SUCCEEDED **`，并在 `build/Build/Products/Debug/EasyContext.app/Contents/PlugIns/` 下生成 `EasyContextFinder.appex`。

> 把生成的 `EasyContext.xcodeproj` 加入 `.gitignore`（由 project.yml 生成，不入库）；`project.yml` 入库。

- [ ] **Step 6: 手动验证扩展注册（人工）**

1. 把构建出的 `build/Build/Products/Debug/EasyContext.app` 拷到 `/Applications/`。
2. 双击运行一次（注册扩展），或 `pluginkit -a /Applications/EasyContext.app/Contents/PlugIns/EasyContextFinder.appex`。
3. 打开「系统设置 → 通用 → 登录项与扩展 → 访达扩展」，勾选 `EasyContextFinder`。
Expected: 列表能看到并启用扩展。若 ad-hoc 扩展无法加载，记录现象（回退见下）。

> **ad-hoc 加载回退**：若系统拒绝加载未受信扩展，尝试 `codesign --force --deep -s - /Applications/EasyContext.app` 重新 ad-hoc 签名后再注册；仍不行则需在 Xcode 用免费 Apple ID 个人团队签名（仅签名，不需 App Group）。把实际可行方式记入报告。

- [ ] **Step 7: 提交**

```bash
git add project.yml EasyContext EasyContextFinder .gitignore
git commit -m "feat(app): XcodeGen 生成宿主 App 与 FinderSync 扩展（ad-hoc 签名，无 App Group）"
```

---

### Task 10: FinderSync 扩展——菜单注入与动作（复制路径 / 打开终端 / 打开编辑器）

**Files:**
- Modify: `EasyContextFinder/FinderSyncExtension.swift`（替换占位为完整实现）

**Interfaces:**
- Consumes: `EasyContextCore`（`ConfigStore`、`Settings`、`KnownApps`、`AppDetector`、`OpenCommand`、`TargetDirectoryResolver`、`RelativePathResolver`、`ProcessSpec`）
- Produces: 右键菜单注入 + 动作；私有 selector `copyFullPath:`、`copyRelativePath:`、`openWithApp:`（经 `representedObject` 带 bundleId）、`newFile:`

- [ ] **Step 1: 实现扩展主类**

`EasyContextFinder/FinderSyncExtension.swift`（整文件替换）：
```swift
import Cocoa
import FinderSync
import EasyContextCore

class FinderSyncExtension: FIFinderSync {
    private let configStore = ConfigStore()

    override init() {
        super.init()
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

        let settings = configStore.load()
        let menu = NSMenu(title: "")

        if settings.copyFullPathEnabled {
            addItem(to: menu, title: "复制完整路径", action: #selector(copyFullPath(_:)))
        }
        if settings.copyRelativePathEnabled {
            addItem(to: menu, title: "复制相对路径", action: #selector(copyRelativePath(_:)))
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
            addItem(to: menu, title: "新建文件…", action: #selector(newFile(_:)))
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
        writeToPasteboard(RelativePathResolver().relativePath(for: url))
    }

    @objc private func openWithApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String,
              let dir = targetDirectory(),
              let app = KnownApps.all.first(where: { $0.bundleId == bundleId })
        else { return }
        run(OpenCommand.open(app: app, directory: dir))
    }

    @objc private func newFile(_ sender: AnyObject?) {
        NewFileController(configStore: configStore).run(in: targetDirectory())
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

> 依赖 Task 12 的 `NewFileController`。本任务先把 `newFile(_:)` 体临时替换为 `NSLog("newFile pending")` 以独立编译；Task 12 恢复真实调用。

- [ ] **Step 2: 临时桩使本任务可编译**

```swift
    @objc private func newFile(_ sender: AnyObject?) {
        NSLog("newFile pending")
    }
```

- [ ] **Step 3: 重新生成并编译**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 真机核对 bundle id（人工）**

对你机器实际安装的终端/编辑器逐个核对，修正 `KnownApp.swift` 中不符的值（尤其 Cursor/Trae）：
Run: `osascript -e 'id of app "Cursor"'`
Expected: 输出与清单一致；不一致则更新 `KnownApp.swift` 并 `cd EasyContextCore && swift test` 回归后单独提交。

- [ ] **Step 5: 手动验证菜单与动作（人工）**

先用设置界面（Task 11）或临时命令写入启用项，再到访达右键目录验证：复制完整/相对路径粘贴正确；「用 VSCode 打开」等能在该目录打开；git 内/外相对路径符合预期。

- [ ] **Step 6: 提交**

```bash
git add EasyContextFinder
git commit -m "feat(finder): 注入复制路径与打开终端/编辑器菜单及动作"
```

---

### Task 11: 宿主 App 设置界面（SwiftUI，基于 ConfigStore）

**Files:**
- Modify: `EasyContext/ContentView.swift`（替换为设置界面）
- Create: `EasyContext/SettingsStore.swift`

**Interfaces:**
- Consumes: `EasyContextCore`（`ConfigStore`、`Settings`、`KnownApps`、`AppDetector`、`FileTemplate`）
- Produces: `@MainActor final class SettingsStore: ObservableObject`，`@Published var settings: Settings`，`persist()`、`detectedTerminals/detectedEditors`、`isEnabled(_:)`、`toggle(_:on:)`

- [ ] **Step 1: 实现 SettingsStore**

`EasyContext/SettingsStore.swift`：
```swift
import Foundation
import AppKit
import EasyContextCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings

    private let store = ConfigStore()

    init() {
        self.settings = store.load()
        seedEnabledIfFirstRun()
    }

    private var detector: AppDetector {
        AppDetector(isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    var detectedTerminals: [KnownApp] { detector.installed(from: KnownApps.terminals) }
    var detectedEditors: [KnownApp] { detector.installed(from: KnownApps.editors) }

    /// 首次运行：默认勾选所有已检测到的 App。
    private func seedEnabledIfFirstRun() {
        if !store.hasStored() {
            settings.enabledTerminalBundleIds = detectedTerminals.map(\.bundleId)
            settings.enabledEditorBundleIds = detectedEditors.map(\.bundleId)
            persist()
        }
    }

    func persist() {
        try? store.save(settings)
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
                ForEach(store.detectedTerminals) { app in appToggle(app) }
                if store.detectedTerminals.isEmpty {
                    Text("未检测到终端").foregroundStyle(.secondary)
                }
            }

            Section("编辑器") {
                ForEach(store.detectedEditors) { app in appToggle(app) }
                if store.detectedEditors.isEmpty {
                    Text("未检测到编辑器").foregroundStyle(.secondary)
                }
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

- [ ] **Step 3: 重新生成并编译**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动验证设置联动（人工）**

运行 App：终端/编辑器列表只显示真实安装的；勾选/取消后，访达右键菜单对应项相应出现/消失（扩展与宿主读同一份 `settings.json`）；关闭「复制相对路径」后该项从菜单消失。

- [ ] **Step 5: 提交**

```bash
git add EasyContext
git commit -m "feat(app): 设置界面读写共享 settings.json、检测已装 App"
```

---

### Task 12: 新建文件动作（输入文件名 + 模板，重名加序号）

**Files:**
- Create: `EasyContextFinder/NewFileController.swift`
- Modify: `EasyContextFinder/FinderSyncExtension.swift`（移除 Task 10 临时桩，恢复真实调用）

**Interfaces:**
- Consumes: `EasyContextCore`（`ConfigStore`、`Settings`、`FileTemplate`、`UniqueNameResolver`）
- Produces: `struct NewFileController(configStore: ConfigStore)`，`func run(in directory: URL?)`

- [ ] **Step 1: 实现 NewFileController**

`EasyContextFinder/NewFileController.swift`：
```swift
import AppKit
import EasyContextCore

struct NewFileController {
    let configStore: ConfigStore

    func run(in directory: URL?) {
        guard let directory else { return }
        let settings = configStore.load()

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

- [ ] **Step 2: 恢复扩展中的真实调用**

把 Task 10 的临时桩改回：
```swift
    @objc private func newFile(_ sender: AnyObject?) {
        NewFileController(configStore: configStore).run(in: targetDirectory())
    }
```

- [ ] **Step 3: 重新生成并编译**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 手动验证新建文件（人工）**

访达右键目录 → 「新建文件…」：弹输入框（默认「未命名」+ 模板下拉）；选 Shell (.sh) 创建 → 出现 `未命名.sh`，含 `#!/bin/bash`，`ls -l` 显示 `-rwxr-xr-x`；再次同名 → `未命名 2.sh`，原文件不被覆盖。
若弹框在扩展上下文无法显示（系统限制），回退：直接用「默认模板 + 未命名」创建并跳过弹框（在 `run` 中加开关），保证功能可用，并记录现象。

- [ ] **Step 5: 提交**

```bash
git add EasyContextFinder
git commit -m "feat(finder): 新建文件（模板 + 重名加序号）"
```

---

### Task 13: 端到端与外置磁盘验证

**Files:** 无新增；整体回归。

**Interfaces:**
- Consumes: 全部已实现功能
- Produces: 一次完整手动验收记录

- [ ] **Step 1: Core 全量自动回归**

Run: `cd EasyContextCore && swift test`
Expected: 全部 PASS。

- [ ] **Step 2: 整工程编译**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 外置磁盘验证（人工）**

插入 U 盘/移动硬盘（挂载 `/Volumes/<名称>`）：在该盘内右键目录 → 菜单正常出现；「复制完整路径」粘贴出 `/Volumes/...`；「用 VSCode 打开」能在外置目录打开；「新建文件…」能在外置盘创建成功。

- [ ] **Step 4: 核心场景清单逐项过（人工）**

逐项确认并记录：复制完整路径、复制相对路径（git 内/外）、各终端打开、各编辑器打开、新建文件（各模板、重名）、文件 vs 目录两种右键起点、设置开关联动、配置写入 `~/Library/Application Support/EasyContext/settings.json`。

- [ ] **Step 5: 提交验收记录（可选）**

```bash
git add -A
git commit -m "test: 端到端与外置磁盘手动验收通过"
```

---

## Self-Review 记录

- **Spec 覆盖**：复制完整路径(T10)、复制相对路径/git根回退(T3+T10)、打开终端自动识别(T4+T10+T11)、打开编辑器(T4+T10+T11)、外置磁盘(T9 监控根 `/` + T13 验证)、新建文件模板+重名加序号(T6+T12)、自动检测(T4+T11)、共享配置(T8 文件存储 + T11)、bundle id/沙盒关闭/macOS13(全局约束 + T9) — 均有对应任务。
- **架构调整**：原 App Group 方案因本机无签名身份/无开发者团队而改为 `~/Library/Application Support/EasyContext/settings.json` 文件存储（沙盒已关，两进程直接读写）；工程改用 XcodeGen + ad-hoc 签名。
- **占位符**：阶段 A、Task 8 含完整代码与可运行命令；T9–T13 含完整源文件/配置，访达 UI 与扩展加载为手动验证（合理）。T10→T12 的临时桩有明确恢复步骤。
- **类型一致性**：`ConfigStore.load/save/hasStored`、`Settings`（纯模型）、`KnownApp`、`AppDetector.installed(from:)`、`OpenCommand.open(app:directory:)`、`RelativePathResolver.relativePath(for:)`、`UniqueNameResolver.uniqueName(base:ext:)`、`FileTemplate`、扩展主类 `FinderSyncExtension` 在定义与消费任务间签名一致。
- **已知风险**：(1) 部分 bundle id 为猜测值 → T10 Step 4 真机核对；(2) ad-hoc 签名的 FinderSync 扩展能否被系统加载存在不确定性 → T9 Step 6 给出 codesign 重签 / 免费个人团队签名回退；(3) 扩展内 `NSAlert` 能否弹出 → T12 Step 4 给出直接创建回退。

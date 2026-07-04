# EasyContext 国际化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 EasyContext（宿主 App + FinderSync 扩展 + Core 包）跟随 macOS 系统语言，支持 7 种语言（简中/英/繁中/日/德/法/西），一次到位。

**Architecture:** 采用 String Catalog（`.xcstrings`），每个 bundle 一份。源语言 `zh-Hans`：现有中文字面量直接作 key。SwiftUI 文案自动本地化；AppKit 文案显式 `String(localized:)`；Core 用 `String(localized:bundle:.module)`。菜单拼接文案改成 `String(localized:)` 插值，生成带位置占位符的格式串以支持各语言语序。

**Tech Stack:** Swift 5/6、SwiftUI、AppKit、Swift Package Manager、XcodeGen 2.45.4、Xcode String Catalog。

## Global Constraints

- 源语言（sourceLanguage）= `zh-Hans`；现有中文字面量即 catalog 的 key，不改源串。
- 支持语言代码固定 7 个：`zh-Hans`、`en`、`zh-Hant`、`ja`、`de`、`fr`、`es`。
- 品牌名绝不翻译：`KnownApp.displayName`、用户自定义 App/命令名、窗口标题 `"Easy Context"`、终端回退名 `"Terminal"`、`FileTemplate.displayName` 中的 `Markdown`/`Shell`/`JSON` 词元、命令示例 `claude`/`codex`。
- 工程级改动只改 `project.yml`（`EasyContext/Info.plist` 和 `EasyContextFinder/Info.plist` 是 XcodeGen 生成物，勿手改），改后 `xcodegen generate` 重生成。
- 部署目标 macOS 13；`String(localized:)` 及其 `locale:` 参数在 macOS 12+ 可用。
- 每份 catalog 的每个 key 必须 7 种语言齐全、无 `needs_review`/未翻译状态。
- 所有译文取自本计划 **Appendix A 术语总表**，逐字使用。

---

### Task 1: 本地化基础设施（XcodeGen 选项 + Package 源语言）

把工程与包配置好本地化：项目开发语言设为 `zh-Hans`、两个 target 声明 `CFBundleLocalizations`、Core 包声明 `defaultLocalization`。本任务不加任何译文，只保证「加了 catalog 后系统认得这些语言、工程能构建」。

**Files:**
- Modify: `project.yml`（顶层 `options` 增 `developmentLanguage`；两个 target 的 `info.properties` 增 `CFBundleLocalizations`）
- Modify: `EasyContextCore/Package.swift:4`（`Package(` 增 `defaultLocalization`）

**Interfaces:**
- Produces: 项目 development region = `zh-Hans`；两 target Info.plist 含 `CFBundleLocalizations`（7 语言）；Core 包 `defaultLocalization: "zh-Hans"`，供后续 Task 放入 `.xcstrings`。

- [ ] **Step 1: 修改 `project.yml` 顶层 options**

在 `options:` 块内（`bundleIdPrefix` 同级）加 `developmentLanguage`：

```yaml
options:
  bundleIdPrefix: com.luyantao.easycontext
  developmentLanguage: zh-Hans
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
```

- [ ] **Step 2: 给两个 target 的 info.properties 加 CFBundleLocalizations**

在 `targets.EasyContext.info.properties` 下（与 `CFBundleDisplayName` 同级）加：

```yaml
        CFBundleLocalizations:
          - zh-Hans
          - en
          - zh-Hant
          - ja
          - de
          - fr
          - es
```

在 `targets.EasyContextFinder.info.properties` 下（与 `CFBundleDisplayName` 同级）加相同的 `CFBundleLocalizations` 块。

- [ ] **Step 3: 修改 `EasyContextCore/Package.swift` 加 defaultLocalization**

```swift
let package = Package(
    name: "EasyContextCore",
    defaultLocalization: "zh-Hans",
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

- [ ] **Step 4: 重生成工程并验证构建**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: BUILD SUCCEEDED。且 `grep -A9 CFBundleLocalizations EasyContext/Info.plist` 显示 7 种语言。

- [ ] **Step 5: 验证 Core 包单独可构建**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context/EasyContextCore && swift build
```
Expected: 编译通过（此时无 catalog，`defaultLocalization` 不报错）。

- [ ] **Step 6: Commit**

```bash
cd /Volumes/Samsung/codes/easy-context
git add project.yml EasyContext/Info.plist EasyContextFinder/Info.plist EasyContextCore/Package.swift EasyContext.xcodeproj
git commit -m "chore(i18n): 本地化基础设施——开发语言 zh-Hans、CFBundleLocalizations、包 defaultLocalization"
```

---

### Task 2: Core 层 FileTemplate 本地化 + Core catalog

`FileTemplate.displayName`（模板选择器/子菜单标题）与 `defaultFileName`（命名面板预填名）改为经 `Bundle.module` 取本地化值，并建 Core 的 String Catalog。这是唯一能真正单元测试的一层。

**Files:**
- Modify: `EasyContextCore/Sources/EasyContextCore/FileTemplate.swift:28-40`
- Create: `EasyContextCore/Sources/EasyContextCore/Localizable.xcstrings`
- Test: `EasyContextCore/Tests/EasyContextCoreTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: `Bundle.module`（SwiftPM 生成的资源包，Task 1 已设 `defaultLocalization`）。
- Produces: `FileTemplate.displayName`、`FileTemplate.defaultFileName` 返回本地化字符串，签名不变（仍是 `String`，无新参数）。

- [ ] **Step 1: 写失败测试**

创建 `EasyContextCore/Tests/EasyContextCoreTests/LocalizationTests.swift`：

```swift
import XCTest
@testable import EasyContextCore

final class LocalizationTests: XCTestCase {
    private let required = ["zh-Hans", "en", "zh-Hant", "ja", "de", "fr", "es"]

    func testCoreBundleContainsAllLanguages() {
        let available = Set(Bundle.module.localizations)
        for code in required {
            XCTAssertTrue(available.contains(code), "Core catalog 缺语言：\(code)（available=\(available.sorted()))")
        }
    }

    func testDefaultFileNameLocalizedBase() {
        // key "未命名" 在英文下应为 "Untitled"，德文下应为 "Unbenannt"。
        let en = String(localized: "未命名", bundle: .module, locale: Locale(identifier: "en"))
        XCTAssertEqual(en, "Untitled")
        let de = String(localized: "未命名", bundle: .module, locale: Locale(identifier: "de"))
        XCTAssertEqual(de, "Unbenannt")
    }

    func testDefaultFileNameKeepsExtension() {
        // 无论语言，扩展名不变。
        XCTAssertTrue(FileTemplate.markdown.defaultFileName.hasSuffix(".md"))
        XCTAssertTrue(FileTemplate.json.defaultFileName.hasSuffix(".json"))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context/EasyContextCore && swift test --filter LocalizationTests
```
Expected: FAIL — `testCoreBundleContainsAllLanguages`/`testDefaultFileNameLocalizedBase` 失败（catalog 尚不存在）。

- [ ] **Step 3: 创建 Core String Catalog**

创建 `EasyContextCore/Sources/EasyContextCore/Localizable.xcstrings`，内容用 Appendix A「CORE 包」小节的 5 个 key，格式如下（此处给出 `未命名` 与 `文本 (.txt)` 两条完整示例，其余 3 个 key 按同结构从 Appendix A 填全）：

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {
    "未命名" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Untitled" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "未命名" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "名称未設定" } },
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Unbenannt" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Sans titre" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Sin título" } }
      }
    },
    "文本 (.txt)" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Text (.txt)" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "文字 (.txt)" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "テキスト (.txt)" } },
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Text (.txt)" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Texte (.txt)" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Texto (.txt)" } }
      }
    },
    "Markdown (.md)" : { "localizations" : { } },
    "Shell (.sh)" : { "localizations" : { } },
    "JSON (.json)" : { "localizations" : { } }
  },
  "version" : "1.0"
}
```

`Markdown (.md)`/`Shell (.sh)`/`JSON (.json)` 三个 key 各语言值与源相同（品牌名不译），`"localizations" : { }` 留空即回退到源语言 `zh-Hans`（=key 本身），符合预期，无需逐语言填。

- [ ] **Step 4: 改 FileTemplate 走本地化**

把 `FileTemplate.swift:28-40` 的 `displayName` 与 `defaultFileName` 改为：

```swift
    public var displayName: String {
        switch self {
        case .markdown: return String(localized: "Markdown (.md)", bundle: .module)
        case .text:     return String(localized: "文本 (.txt)", bundle: .module)
        case .shell:    return String(localized: "Shell (.sh)", bundle: .module)
        case .json:     return String(localized: "JSON (.json)", bundle: .module)
        }
    }

    /// 命名面板预填的默认完整文件名（如「未命名.md」）。
    public var defaultFileName: String {
        String(localized: "未命名", bundle: .module) + "." + fileExtension
    }
```

- [ ] **Step 5: 运行测试确认通过**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context/EasyContextCore && swift test --filter LocalizationTests
```
Expected: PASS（3 个测试全绿）。若报 unhandled resource 警告导致 catalog 未进包，则在 `Package.swift` 的 `.target(name: "EasyContextCore")` 加 `resources: [.process("Localizable.xcstrings")]` 后重跑。

- [ ] **Step 6: 跑全量 Core 测试确认无回归**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context/EasyContextCore && swift test
```
Expected: 所有既有测试 + 新测试全绿。

- [ ] **Step 7: Commit**

```bash
cd /Volumes/Samsung/codes/easy-context
git add EasyContextCore/Sources/EasyContextCore/FileTemplate.swift EasyContextCore/Sources/EasyContextCore/Localizable.xcstrings EasyContextCore/Tests/EasyContextCoreTests/LocalizationTests.swift EasyContextCore/Package.swift
git commit -m "feat(i18n): Core 模板名与默认文件名本地化（7 语言）"
```

---

### Task 3: FinderSync 扩展本地化（含菜单拼接改造）

扩展是 AppKit + 独立沙盒 bundle。把 5 处硬编码菜单文案改成 `String(localized:)`；其中三处拼接标题改成插值格式串（生成位置占位符）。新建扩展 catalog。

**Files:**
- Modify: `EasyContextFinder/FinderSyncExtension.swift:104,108,120,126,147,155,157`
- Create: `EasyContextFinder/Localizable.xcstrings`

**Interfaces:**
- Consumes: 扩展 main bundle（`String(localized:)` 默认 bundle）。
- Produces: 右键菜单所有框架文案本地化；`template.displayName`（来自 Core `.module`）已在 Task 2 本地化。

- [ ] **Step 1: 改静态菜单标题为 String(localized:)**

`FinderSyncExtension.swift` 中：

第 104 行 `title: "复制路径"` → `title: String(localized: "复制路径")`
第 108 行 `title: "复制相对路径"` → `title: String(localized: "复制相对路径")`

- [ ] **Step 2: 改三处拼接标题为插值格式串**

第 120 行：
```swift
            let item = addItem(to: menu, title: String(localized: "用 \(app.name) 打开终端"),
```
第 126 行：
```swift
            let item = addItem(to: menu, title: String(localized: "用 \(app.name) 打开"),
```
第 147 行（两个参数，顺序为 term、cmd）：
```swift
                let item = addItem(to: menu, title: String(localized: "用 \(termName) 运行 \(cmd.name)"),
```
`String(localized:)` 会把 `\(app.name)` 生成 `%@` 键、把两参数生成 `用 %@ 运行 %@` 键；各语言在 catalog 里用 `%1$@`/`%2$@` 换序。

- [ ] **Step 3: 改「新建文件」标题**

第 155 行 `NSMenuItem(title: "新建文件", ...)` → `NSMenuItem(title: String(localized: "新建文件"), ...)`
第 157 行 `NSMenu(title: "新建文件")` 是内部标题（不显示给用户），可保持原样不改。

- [ ] **Step 4: 创建扩展 String Catalog**

创建 `EasyContextFinder/Localizable.xcstrings`，包含 Appendix A「EXT 扩展」小节的全部 key（`复制路径`、`复制相对路径`、`用 %@ 打开终端`、`用 %@ 打开`、`用 %@ 运行 %@`、`新建文件`），每个 key 6 种目标语言值取自 Appendix A。`用 %@ 运行 %@` 的各语言值须用 `%1$@`（终端名）/`%2$@`（命令名）标注顺序。格式示例（`用 %@ 运行 %@` 一条）：

```json
    "用 %@ 运行 %@" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Run %2$@ in %1$@" } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "在 %1$@ 執行 %2$@" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "%1$@ で %2$@ を実行" } },
        "de" : { "stringUnit" : { "state" : "translated", "value" : "%2$@ in %1$@ ausführen" } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Exécuter %2$@ dans %1$@" } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Ejecutar %2$@ en %1$@" } }
      }
    }
```

- [ ] **Step 5: 重生成并构建**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 6: 验证扩展 bundle 含 7 语言**

Run:
```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "EasyContext.app" -path "*Debug*" 2>/dev/null | head -1)
ls "$APP/Contents/PlugIns/EasyContextFinder.appex/Contents/Resources/" | grep -E "\.lproj|xcstrings|Localizable"
```
Expected: 能看到编译进扩展的本地化资源（`Localizable.loctable` 或各 `.lproj`）。这是 spec 主要风险点的直接验证。

- [ ] **Step 7: Commit**

```bash
cd /Volumes/Samsung/codes/easy-context
git add EasyContextFinder/FinderSyncExtension.swift EasyContextFinder/Localizable.xcstrings EasyContext.xcodeproj
git commit -m "feat(i18n): FinderSync 右键菜单本地化 + 拼接标题改位置占位符格式串"
```

---

### Task 4: 宿主 App 的 AppKit 文案本地化

宿主里所有 AppKit 文案（不会自动本地化）显式包 `String(localized:)`：应用主菜单、命名面板、两个 URL 处理器的 `NSAlert`、`ContentView` 里的 `NSOpenPanel`/`NSAlert`、`SettingsStore` 默认命令名。

**Files:**
- Modify: `EasyContext/EasyContextApp.swift:98,101,107,108,114,115,116,117,118`
- Modify: `EasyContext/NameInputController.swift:24,34,38,44`
- Modify: `EasyContext/CommandLauncher.swift:33,49`
- Modify: `EasyContext/NewFileLauncher.swift:30,31`
- Modify: `EasyContext/ContentView.swift:357,369,370,371,372`
- Modify: `EasyContext/SettingsStore.swift:238,241`

**Interfaces:**
- Consumes: App main bundle。
- Produces: 所有 AppKit 文案本地化；对应 key 将在 Task 5 的 App catalog 中补齐译文。

- [ ] **Step 1: EasyContextApp 主菜单**

`EasyContextApp.swift` `setupMenu()` 内，把各 `addItem(withTitle:)` / `NSMenu(title:)` 的中文字面量包起来：

```swift
        appMenu.addItem(withTitle: String(localized: "隐藏 Easy Context"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "退出 Easy Context"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: String(localized: "文件"))
        fileMenu.addItem(withTitle: String(localized: "关闭窗口"),
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: String(localized: "编辑"))
        editMenu.addItem(withTitle: String(localized: "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: String(localized: "拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: String(localized: "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
```

`win.title = "Easy Context"`（第 65 行）是品牌名，保持不变。

- [ ] **Step 2: NameInputController**

```swift
        let label = NSTextField(labelWithString: String(localized: "输入文件名："))
```
```swift
        window.title = String(localized: "新建文件")
```
```swift
        let cancel = NSButton(title: String(localized: "取消"), target: self, action: #selector(onCancel))
```
```swift
        let create = NSButton(title: String(localized: "创建"), target: self, action: #selector(onCreate))
```

- [ ] **Step 3: CommandLauncher 两处 NSAlert**

第 33 行：
```swift
            notify(String(localized: "无法运行"),
                   String(localized: "“\(term)” 未配置启动模板，请在 EasyContext 设置里为它填写模板。"))
```
第 49 行：
```swift
        do { try process.run() } catch { notify(String(localized: "运行失败"), error.localizedDescription) }
```

- [ ] **Step 4: NewFileLauncher NSAlert**

第 30–31 行：
```swift
            a.messageText = String(localized: "新建文件失败")
            a.informativeText = String(localized: "无法在该目录创建文件。")
```

- [ ] **Step 5: ContentView 的 AppKit 部分（NSOpenPanel + NSAlert）**

第 357 行：
```swift
        panel.prompt = String(localized: "添加")
```
`promptUnsupported` 内（第 369–372 行）：
```swift
        alert.messageText = String(localized: "“\(name)” 可能不支持以目录方式打开")
        alert.informativeText = String(localized: "该应用未声明可打开文件夹，从右键菜单点击它时可能无法正常打开目录。仍要添加吗？")
        alert.addButton(withTitle: String(localized: "仍然添加"))
        alert.addButton(withTitle: String(localized: "取消"))
```

- [ ] **Step 6: SettingsStore 默认命令名**

`addCommand()`（第 236–242 行）改为本地化基名：
```swift
    func addCommand() {
        let base = String(localized: "命令")
        var name = base
        var n = 1
        while settings.commands.contains(where: { $0.name == name }) {
            n += 1
            name = "\(base)\(n)"
        }
        settings.commands.append(CommandEntry(name: name, command: "", enabled: true))
        persist()
    }
```

- [ ] **Step 7: 构建确认编译通过**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: BUILD SUCCEEDED（此步只验证语法；译文在 Task 5 补，未翻译时回退中文源不影响编译）。

- [ ] **Step 8: Commit**

```bash
cd /Volumes/Samsung/codes/easy-context
git add EasyContext/EasyContextApp.swift EasyContext/NameInputController.swift EasyContext/CommandLauncher.swift EasyContext/NewFileLauncher.swift EasyContext/ContentView.swift EasyContext/SettingsStore.swift
git commit -m "refactor(i18n): 宿主 App 所有 AppKit 文案改 String(localized:)"
```

---

### Task 5: 宿主 App catalog（SwiftUI 自动 + 全部译文）

`ContentView` 的 SwiftUI `Text/Button/Picker/TextField/.help` 字面量会被编译器自动抽取进 App catalog（无需改代码）。本任务建 App catalog 并补齐 Task 4 + SwiftUI 全部 key 的 7 语言译文。

**Files:**
- Create: `EasyContext/Localizable.xcstrings`
- Modify: `EasyContext.xcodeproj`（xcodegen 重生成纳入 catalog 资源）

**Interfaces:**
- Consumes: Task 4 产生的 `String(localized:)` key + `ContentView` 的 SwiftUI 字面量 key。
- Produces: App bundle 含 7 语言全部 UI 文案。

- [ ] **Step 1: 创建 App String Catalog**

创建 `EasyContext/Localizable.xcstrings`，`sourceLanguage` = `zh-Hans`，`strings` 包含 Appendix A「APP 宿主」小节列出的全部 key，每个 key 6 种目标语言值取自 Appendix A。含参数的 key（`“%@” 可能不支持以目录方式打开`、`“%@” 未配置启动模板，请在 EasyContext 设置里为它填写模板。`）用 `%@` 占位。JSON 结构同 Task 2 Step 3 示例。

- [ ] **Step 2: 重生成工程**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context && xcodegen generate
```
Expected: 无报错；`EasyContext/Localizable.xcstrings` 被纳入 App target 资源。

- [ ] **Step 3: 构建**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 验证 App bundle 含 7 语言且无「未翻译」硬编码遗漏**

Run:
```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "EasyContext.app" -path "*Debug*" 2>/dev/null | head -1)
plutil -extract CFBundleLocalizations raw "$APP/Contents/Info.plist"
ls "$APP/Contents/Resources/" | grep -E "\.lproj|loctable|xcstrings"
```
Expected: 列出 7 语言；资源里有本地化产物。

- [ ] **Step 5: Commit**

```bash
cd /Volumes/Samsung/codes/easy-context
git add EasyContext/Localizable.xcstrings EasyContext.xcodeproj
git commit -m "feat(i18n): 宿主 App 设置页/弹窗全部文案本地化（7 语言）"
```

---

### Task 6: Info.plist 授权说明本地化

`NSAppleEventsUsageDescription`（自动化授权弹窗里那句话）用 InfoPlist String Catalog 本地化。

**Files:**
- Create: `EasyContext/InfoPlist.xcstrings`
- Modify: `EasyContext.xcodeproj`（重生成纳入）

**Interfaces:**
- Consumes: `project.yml` 里 `NSAppleEventsUsageDescription` 的中文基值（作为 `zh-Hans` 源）。
- Produces: 授权说明 7 语言本地化。

- [ ] **Step 1: 创建 InfoPlist catalog**

创建 `EasyContext/InfoPlist.xcstrings`，`sourceLanguage` = `zh-Hans`，含单 key `NSAppleEventsUsageDescription`，源值 = `用于在你选择的终端里运行命令（如 claude / codex）。`，6 种目标语言值取自 Appendix A「INFOPLIST」小节：

```json
{
  "sourceLanguage" : "zh-Hans",
  "strings" : {
    "NSAppleEventsUsageDescription" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Used to run commands (such as claude / codex) in the terminal you choose." } },
        "zh-Hant" : { "stringUnit" : { "state" : "translated", "value" : "用於在你選擇的終端機中執行指令（例如 claude / codex）。" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "選択したターミナルでコマンド（claude / codex など）を実行するために使用します。" } },
        "de" : { "stringUnit" : { "state" : "translated", "value" : "Wird verwendet, um Befehle (z. B. claude / codex) im gewählten Terminal auszuführen." } },
        "fr" : { "stringUnit" : { "state" : "translated", "value" : "Utilisé pour exécuter des commandes (comme claude / codex) dans le terminal de votre choix." } },
        "es" : { "stringUnit" : { "state" : "translated", "value" : "Se usa para ejecutar comandos (como claude / codex) en la terminal que elijas." } }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 2: 重生成并构建**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug build CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 验证**

Run:
```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData -name "EasyContext.app" -path "*Debug*" 2>/dev/null | head -1)
ls "$APP/Contents/Resources/en.lproj/" 2>/dev/null | grep -i infoplist || find "$APP/Contents/Resources" -name "*InfoPlist*"
```
Expected: 存在 InfoPlist 本地化产物（`InfoPlist.loctable` 或各语言 `.lproj/InfoPlist.strings`）。

- [ ] **Step 4: Commit**

```bash
cd /Volumes/Samsung/codes/easy-context
git add EasyContext/InfoPlist.xcstrings EasyContext.xcodeproj
git commit -m "feat(i18n): 自动化授权说明（NSAppleEventsUsageDescription）本地化"
```

---

### Task 7: 全量验证（伪本地化 + 实机切换 + 扩展）

无法用单元测试覆盖的 GUI/系统层，做结构化人工验证。

**Files:** 无（仅验证）。

- [ ] **Step 1: catalog 完整性检查（无未翻译）**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context
grep -L '"needs_review"\|"new"' EasyContext/Localizable.xcstrings EasyContextFinder/Localizable.xcstrings EasyContextCore/Sources/EasyContextCore/Localizable.xcstrings EasyContext/InfoPlist.xcstrings
python3 -c "import json,sys; [json.load(open(p)) for p in ['EasyContext/Localizable.xcstrings','EasyContextFinder/Localizable.xcstrings','EasyContextCore/Sources/EasyContextCore/Localizable.xcstrings','EasyContext/InfoPlist.xcstrings']]; print('all catalogs valid JSON')"
```
Expected: 四个 catalog 均为合法 JSON、无 `needs_review`/`new` 状态。

- [ ] **Step 2: 伪本地化构建（查截断/漏译）**

在 Xcode 打开 `EasyContext.xcodeproj`，Product → Scheme → Edit Scheme → Run → Options → App Language 选 **Double-Length Pseudolanguage / Accented Pseudolanguage**，运行 App，逐屏检查设置页有无截断、有无仍是中文的硬编码遗漏。
Expected: 所有可见文案均被伪本地化包裹（无裸中文），布局无严重截断。

- [ ] **Step 3: 实机语言切换（宿主设置页）**

系统设置 → 语言与地区，依次将首选语言临时切到 English、日本語、Deutsch，每次重开 App 设置窗，核对设置页、命名面板、弹窗文案。
Expected: 三种语言下文案正确；品牌名（VS Code、iTerm 等）未被翻译。

- [ ] **Step 4: 实机语言切换（FinderSync 右键菜单）**

保持某非中文系统语言，重启 Finder 扩展并测右键菜单：
```bash
pluginkit -e ignore -i com.luyantao.easycontext.finder 2>/dev/null; \
killall Finder; open -b com.luyantao.easycontext.finder 2>/dev/null
```
或在「系统设置 → 隐私与安全性 → 扩展 → 访达扩展」里关开一次。右键任意文件夹，检查「复制路径」「用 X 打开」「用 X 运行 Y」「新建文件」及子菜单模板名。
Expected: 菜单文案随系统语言；日/德语的「用 X 运行 Y」语序正确（占位符换序生效）；`template.displayName` 子菜单本地化正确（验证 Core `.module` 在扩展内可用——spec 第二风险点）。

- [ ] **Step 5: 回归 + 恢复系统语言**

Run:
```bash
cd /Volumes/Samsung/codes/easy-context/EasyContextCore && swift test
```
Expected: 全绿。随后把系统首选语言恢复为简体中文。

- [ ] **Step 6: 更新 README 语言说明并提交**

在 `README.md` 适当位置补一句「支持 7 种语言，跟随系统自动切换」。
```bash
cd /Volumes/Samsung/codes/easy-context
git add README.md
git commit -m "docs(i18n): README 补充多语言支持说明"
```

---

## Appendix A：术语总表（所有译文的唯一来源）

列顺序：`zh-Hans`(源/key) | `en` | `zh-Hant` | `ja` | `de` | `fr` | `es`

### CORE 包（`EasyContextCore/.../Localizable.xcstrings`）

| key (zh-Hans) | en | zh-Hant | ja | de | fr | es |
|---|---|---|---|---|---|---|
| 未命名 | Untitled | 未命名 | 名称未設定 | Unbenannt | Sans titre | Sin título |
| 文本 (.txt) | Text (.txt) | 文字 (.txt) | テキスト (.txt) | Text (.txt) | Texte (.txt) | Texto (.txt) |
| Markdown (.md) | *(同源)* | *(同源)* | *(同源)* | *(同源)* | *(同源)* | *(同源)* |
| Shell (.sh) | *(同源)* | *(同源)* | *(同源)* | *(同源)* | *(同源)* | *(同源)* |
| JSON (.json) | *(同源)* | *(同源)* | *(同源)* | *(同源)* | *(同源)* | *(同源)* |

*(同源)* = 该语言 `localizations` 留空，回退到源值。

### EXT 扩展（`EasyContextFinder/Localizable.xcstrings`）

| key (zh-Hans) | en | zh-Hant | ja | de | fr | es |
|---|---|---|---|---|---|---|
| 复制路径 | Copy Path | 複製路徑 | パスをコピー | Pfad kopieren | Copier le chemin | Copiar ruta |
| 复制相对路径 | Copy Relative Path | 複製相對路徑 | 相対パスをコピー | Relativen Pfad kopieren | Copier le chemin relatif | Copiar ruta relativa |
| 用 %@ 打开终端 | Open Terminal with %@ | 以 %@ 開啟終端機 | %@ でターミナルを開く | Terminal mit %@ öffnen | Ouvrir le terminal avec %@ | Abrir terminal con %@ |
| 用 %@ 打开 | Open with %@ | 以 %@ 開啟 | %@ で開く | Mit %@ öffnen | Ouvrir avec %@ | Abrir con %@ |
| 用 %@ 运行 %@ | Run %2$@ in %1$@ | 在 %1$@ 執行 %2$@ | %1$@ で %2$@ を実行 | %2$@ in %1$@ ausführen | Exécuter %2$@ dans %1$@ | Ejecutar %2$@ en %1$@ |
| 新建文件 | New File | 新增檔案 | 新規ファイル | Neue Datei | Nouveau fichier | Nuevo archivo |

### APP 宿主（`EasyContext/Localizable.xcstrings`）

| key (zh-Hans) | en | zh-Hant | ja | de | fr | es |
|---|---|---|---|---|---|---|
| 隐藏 Easy Context | Hide Easy Context | 隱藏 Easy Context | Easy Context を隠す | Easy Context ausblenden | Masquer Easy Context | Ocultar Easy Context |
| 退出 Easy Context | Quit Easy Context | 結束 Easy Context | Easy Context を終了 | Easy Context beenden | Quitter Easy Context | Salir de Easy Context |
| 文件 | File | 檔案 | ファイル | Ablage | Fichier | Archivo |
| 关闭窗口 | Close Window | 關閉視窗 | ウインドウを閉じる | Fenster schließen | Fermer la fenêtre | Cerrar ventana |
| 编辑 | Edit | 編輯 | 編集 | Bearbeiten | Édition | Edición |
| 剪切 | Cut | 剪下 | カット | Ausschneiden | Couper | Cortar |
| 拷贝 | Copy | 拷貝 | コピー | Kopieren | Copier | Copiar |
| 粘贴 | Paste | 貼上 | ペースト | Einsetzen | Coller | Pegar |
| 全选 | Select All | 全選 | すべてを選択 | Alles auswählen | Tout sélectionner | Seleccionar todo |
| 输入文件名： | Enter file name: | 輸入檔案名稱： | ファイル名を入力： | Dateiname eingeben: | Saisir le nom du fichier : | Introduce el nombre del archivo: |
| 新建文件 | New File | 新增檔案 | 新規ファイル | Neue Datei | Nouveau fichier | Nuevo archivo |
| 取消 | Cancel | 取消 | キャンセル | Abbrechen | Annuler | Cancelar |
| 创建 | Create | 建立 | 作成 | Erstellen | Créer | Crear |
| 无法运行 | Cannot Run | 無法執行 | 実行できません | Ausführung nicht möglich | Impossible d'exécuter | No se puede ejecutar |
| “%@” 未配置启动模板，请在 EasyContext 设置里为它填写模板。 | “%@” has no launch template configured. Please add one in EasyContext settings. | 「%@」尚未設定啟動範本，請在 EasyContext 設定中為它填寫範本。 | 「%@」に起動テンプレートが設定されていません。EasyContext の設定でテンプレートを入力してください。 | Für „%@“ ist keine Startvorlage konfiguriert. Bitte lege in den EasyContext-Einstellungen eine an. | Aucun modèle de lancement n'est configuré pour « %@ ». Ajoutez-en un dans les réglages d'EasyContext. | «%@» no tiene una plantilla de inicio configurada. Añádela en los ajustes de EasyContext. |
| 运行失败 | Run Failed | 執行失敗 | 実行に失敗しました | Ausführung fehlgeschlagen | Échec de l'exécution | Error al ejecutar |
| 新建文件失败 | Failed to Create File | 新增檔案失敗 | ファイルの作成に失敗しました | Datei konnte nicht erstellt werden | Échec de la création du fichier | Error al crear el archivo |
| 无法在该目录创建文件。 | Could not create a file in this folder. | 無法在該目錄建立檔案。 | このフォルダにファイルを作成できませんでした。 | In diesem Ordner konnte keine Datei erstellt werden. | Impossible de créer un fichier dans ce dossier. | No se pudo crear un archivo en esta carpeta. |
| 菜单显示的编辑器 | Editors shown in menu | 選單顯示的編輯器 | メニューに表示するエディタ | Im Menü angezeigte Editoren | Éditeurs affichés dans le menu | Editores mostrados en el menú |
| 菜单显示的终端 | Terminals shown in menu | 選單顯示的終端機 | メニューに表示するターミナル | Im Menü angezeigte Terminals | Terminaux affichés dans le menu | Terminales mostrados en el menú |
| 菜单项 | Menu Items | 選單項目 | メニュー項目 | Menüeinträge | Éléments du menu | Elementos del menú |
| 复制路径 | Copy Path | 複製路徑 | パスをコピー | Pfad kopieren | Copier le chemin | Copiar ruta |
| 复制相对路径 | Copy Relative Path | 複製相對路徑 | 相対パスをコピー | Relativen Pfad kopieren | Copier le chemin relatif | Copiar ruta relativa |
| 应用图标 | App Icon | 應用程式圖示 | アプリアイコン | App-Symbol | Icône de l'app | Icono de la app |
| 黑白 | Monochrome | 黑白 | モノクロ | Schwarzweiß | Monochrome | Monocromo |
| 彩色 | Color | 彩色 | カラー | Farbig | Couleur | Color |
| 其他 | Other | 其他 | その他 | Sonstiges | Autre | Otros |
| 打开配置目录 | Open Config Folder | 開啟設定目錄 | 設定フォルダを開く | Konfigurationsordner öffnen | Ouvrir le dossier de configuration | Abrir carpeta de configuración |
| 访达扩展设置 | Finder Extension Settings | Finder 擴充功能設定 | Finder 機能拡張の設定 | Finder-Erweiterungseinstellungen | Réglages de l'extension Finder | Ajustes de la extensión del Finder |
| 自定义命令 | Custom Commands | 自訂指令 | カスタムコマンド | Eigene Befehle | Commandes personnalisées | Comandos personalizados |
| ⚠ 该终端从外部运行命令会弹确认且可能多开窗口，建议改用 Terminal / iTerm | ⚠ Running commands externally in this terminal may prompt for confirmation and open extra windows. Use Terminal / iTerm instead. | ⚠ 此終端機從外部執行指令會跳出確認且可能開啟多個視窗，建議改用 Terminal / iTerm | ⚠ このターミナルで外部からコマンドを実行すると確認が表示され、複数のウインドウが開くことがあります。Terminal / iTerm の使用をおすすめします。 | ⚠ Wenn Befehle extern in diesem Terminal ausgeführt werden, erscheint eine Bestätigung und es öffnen sich ggf. mehrere Fenster. Verwende stattdessen Terminal / iTerm. | ⚠ L'exécution externe de commandes dans ce terminal peut demander une confirmation et ouvrir plusieurs fenêtres. Utilisez plutôt Terminal / iTerm. | ⚠ Ejecutar comandos externamente en esta terminal puede pedir confirmación y abrir varias ventanas. Usa Terminal / iTerm en su lugar. |
| 执行终端 | Run in terminal | 執行終端機 | 実行ターミナル | Ausführungsterminal | Terminal d'exécution | Terminal de ejecución |
| 名称 | Name | 名稱 | 名前 | Name | Nom | Nombre |
| 命令，如 claude | Command, e.g. claude | 指令，例如 claude | コマンド（例：claude） | Befehl, z. B. claude | Commande, p. ex. claude | Comando, p. ej. claude |
| 新增命令 | Add command | 新增指令 | コマンドを追加 | Befehl hinzufügen | Ajouter une commande | Añadir comando |
| 删除选中的命令 | Delete selected command | 刪除所選指令 | 選択したコマンドを削除 | Ausgewählten Befehl löschen | Supprimer la commande sélectionnée | Eliminar el comando seleccionado |
| 自定义 | Custom | 自訂 | カスタム | Eigen | Perso | Personalizado |
| 添加自定义 App | Add custom app | 新增自訂 App | カスタム App を追加 | Eigene App hinzufügen | Ajouter une app perso | Añadir app personalizada |
| 移除选中的自定义项（内置项不可删） | Remove selected custom item (built-in items can't be removed) | 移除所選自訂項目（內建項目無法移除） | 選択したカスタム項目を削除（内蔵項目は削除不可） | Ausgewähltes eigenes Objekt entfernen (integrierte lassen sich nicht entfernen) | Retirer l'élément perso sélectionné (les éléments intégrés ne peuvent pas être retirés) | Quitar el elemento personalizado seleccionado (los integrados no se pueden quitar) |
| 配置文件损坏，已备份为 config.json.bak，当前使用默认设置 | Config file is corrupted. It was backed up as config.json.bak; using default settings. | 設定檔已損毀，已備份為 config.json.bak，目前使用預設設定 | 設定ファイルが破損しています。config.json.bak としてバックアップし、デフォルト設定を使用中です。 | Konfigurationsdatei ist beschädigt. Sie wurde als config.json.bak gesichert; Standardeinstellungen werden verwendet. | Le fichier de configuration est corrompu. Il a été sauvegardé sous config.json.bak ; réglages par défaut utilisés. | El archivo de configuración está dañado. Se guardó como config.json.bak; se usan los ajustes predeterminados. |
| 访达扩展尚未启用，右键菜单不会出现 | The Finder extension isn't enabled yet, so the right-click menu won't appear. | Finder 擴充功能尚未啟用，右鍵選單不會出現 | Finder 機能拡張がまだ有効になっていないため、右クリックメニューは表示されません。 | Die Finder-Erweiterung ist noch nicht aktiviert, daher erscheint das Rechtsklick-Menü nicht. | L'extension Finder n'est pas encore activée, le menu clic droit n'apparaîtra pas. | La extensión del Finder aún no está activada, por lo que el menú contextual no aparecerá. |
| 去启用 | Enable | 前往啟用 | 有効にする | Aktivieren | Activer | Activar |
| 重新检测 | Re-check | 重新偵測 | 再検出 | Erneut prüfen | Revérifier | Volver a comprobar |
| 添加 | Add | 新增 | 追加 | Hinzufügen | Ajouter | Añadir |
| “%@” 可能不支持以目录方式打开 | “%@” may not support opening folders | 「%@」可能不支援以目錄方式開啟 | 「%@」はフォルダを開くことに対応していない可能性があります | „%@“ unterstützt möglicherweise kein Öffnen von Ordnern | « %@ » ne prend peut-être pas en charge l'ouverture de dossiers | «%@» podría no admitir la apertura de carpetas |
| 该应用未声明可打开文件夹，从右键菜单点击它时可能无法正常打开目录。仍要添加吗？ | This app doesn't declare that it can open folders, so clicking it from the right-click menu may not open the directory. Add it anyway? | 此應用程式未宣告可開啟資料夾，從右鍵選單點按它時可能無法正常開啟目錄。仍要新增嗎？ | この App はフォルダを開けると宣言していないため、右クリックメニューから選んでもディレクトリを開けないことがあります。追加しますか？ | Diese App gibt nicht an, dass sie Ordner öffnen kann. Beim Klick aus dem Rechtsklick-Menü wird das Verzeichnis möglicherweise nicht geöffnet. Trotzdem hinzufügen? | Cette app ne déclare pas pouvoir ouvrir des dossiers ; en cliquant depuis le menu clic droit, le répertoire pourrait ne pas s'ouvrir. L'ajouter quand même ? | Esta app no declara que pueda abrir carpetas, así que al hacer clic desde el menú contextual puede que no abra el directorio. ¿Añadirla de todos modos? |
| 仍然添加 | Add Anyway | 仍要新增 | 追加する | Trotzdem hinzufügen | Ajouter quand même | Añadir de todos modos |
| 命令 | Command | 指令 | コマンド | Befehl | Commande | Comando |

### INFOPLIST（`EasyContext/InfoPlist.xcstrings`）

| key | en | zh-Hant | ja | de | fr | es |
|---|---|---|---|---|---|---|
| NSAppleEventsUsageDescription | Used to run commands (such as claude / codex) in the terminal you choose. | 用於在你選擇的終端機中執行指令（例如 claude / codex）。 | 選択したターミナルでコマンド（claude / codex など）を実行するために使用します。 | Wird verwendet, um Befehle (z. B. claude / codex) im gewählten Terminal auszuführen. | Utilisé pour exécuter des commandes (comme claude / codex) dans le terminal de votre choix. | Se usa para ejecutar comandos (como claude / codex) en la terminal que elijas. |

（源语言 `zh-Hans` 值 = `用于在你选择的终端里运行命令（如 claude / codex）。`）

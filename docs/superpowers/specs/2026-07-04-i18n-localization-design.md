# EasyContext 国际化（i18n）设计

日期：2026-07-04
状态：待评审

## 目标

为 EasyContext 增加多语言支持，跟随 macOS 系统语言自动切换，无需用户手动配置、无需应用内切换开关。**一次到位交付全部 7 种语言。**

支持语言（共 7 种）：

| 代码 | 语言 |
|------|------|
| `zh-Hans` | 简体中文（源语言 / source language） |
| `en` | 英语 |
| `zh-Hant` | 繁体中文（独立用词，非简中转换） |
| `ja` | 日语 |
| `de` | 德语 |
| `fr` | 法语 |
| `es` | 西班牙语 |

**本地化范围**（仅用户直接可见的框架文案）：

- FinderSync 右键菜单项
- 设置页（`ContentView`）全部文案
- 弹窗（`NSAlert` / `NSOpenPanel` / 命名面板）
- 新建文件的默认文件名与模板名
- 状态栏菜单、Info.plist 中的展示名与授权说明

**不在范围**：Core 层内部错误信息、代码注释、日志。

## 关键设计决策

### 决策 1：跟随系统，不做应用内切换

macOS 会根据「系统设置 → 语言与地区」自动匹配已提供的本地化资源，找不到则回退到源语言。因此**不写任何语言检测代码**，也**不需要**在宿主 App 与 FinderSync 扩展间同步语言状态——两个 bundle 各自被系统按同一套系统偏好本地化。

### 决策 2：技术方案 = String Catalog（`.xcstrings`），每个 target 一份

采用 Xcode 15+ 的 String Catalog，而非老式 `.strings`。项目有三个独立 bundle，本地化资源不共享，故三份 catalog：

| Bundle | 类型 | catalog 位置 |
|--------|------|-------------|
| 宿主 App `EasyContext` | SwiftUI + AppKit | `EasyContext/Localizable.xcstrings` |
| FinderSync 扩展 | AppKit | `EasyContextFinder/Localizable.xcstrings` |
| `EasyContextCore` 包 | SPM | `EasyContextCore/Sources/EasyContextCore/Resources/Localizable.xcstrings` |

- **源语言（source language）= `zh-Hans`**：现有源码字面量即中文，源码几乎不改动字面量，对中文维护者可读性最好；简中作为 source 免翻，其余 6 种（含英语）作为并列翻译填充。
- SwiftUI 的 `Text("...")` 接受 `LocalizedStringKey`，**自动**进 catalog、自动本地化。
- AppKit（`NSAlert`、`NSMenuItem(title:)`、`NSOpenPanel.prompt`、`.help(...)`）**不会**自动本地化，须显式包 `String(localized:)`。
- SPM 包须在 `Package.swift` 设 `defaultLocalization: "zh-Hans"` 并声明 resources；取字符串走 `String(localized:bundle: .module)`。

### 决策 3：菜单拼接文案改造为带占位符的格式串（本次唯一逻辑改动）

`FinderSyncExtension` 现用字符串插值拼接菜单标题：

```swift
"用 \(app.name) 打开终端"        // en: "Open Terminal with %@"
"用 \(app.name) 打开"            // en: "Open with %@"
"用 \(termName) 运行 \(cmd.name)" // en: "Run %2$@ in %1$@"
```

各语言语序不同（日语动词后置、德语框式结构），**不能**直接拼英文。改为带**位置占位符**的本地化格式串，用 `%1$@` / `%2$@` 显式编号，由每种语言自行决定占位符顺序，保证可换序。

改造点（`FinderSyncExtension.swift`）：`menu(for:)` 内三处 `addItem(... title:)` 及新建文件子菜单标题。

### 决策 4：品牌名不翻译

`KnownApp.displayName`（Terminal / iTerm / VS Code / Cursor / …）是品牌名，**绝不翻译**；用户自定义 App/命令名是用户数据，不动。只翻译其周围框架文案。`ContentView` 中 `Text(entry.name)`、`Text(t.name)` 保持原样。

### 决策 5：新建文件默认名随语言本地化

模板名与预填默认文件名随语言变，例如：

| 模板 | zh-Hans | en |
|------|---------|-----|
| markdown | Markdown 文档 / 未命名 | Markdown Document / Untitled |
| text | 文本文件 / 未命名 | Text File / Untitled |
| shell | Shell 脚本 / 未命名 | Shell Script / Untitled |
| json | JSON 文件 / 未命名 | JSON File / Untitled |

`FileTemplate.displayName` 与默认文件名改为经由 Core 的 catalog（`.module`）取本地化值。

### 决策 6：Info.plist 与 XcodeGen

项目用 XcodeGen（`project.yml` 生成 `.xcodeproj`），所有工程级改动写进 `project.yml`：

- 两个 target 增加 `CFBundleDevelopmentRegion = zh-Hans`。
- 两个 target 增加 `CFBundleLocalizations`（列出 7 种语言代码）。
- `CFBundleDisplayName`、`NSAppleEventsUsageDescription` 经 InfoPlist String Catalog 本地化。

### 决策 7：繁中独立用词，不用简中糊弄

繁中（`zh-Hant`）单独逐条翻译，遵循台湾/香港惯用词。钉死对照（节选）：

| 简中 | 繁中 |
|------|------|
| 文件 | 檔案 |
| 设置 | 設定 |
| 复制 | 複製 |
| 启用 | 啟用 |
| 终端 | 終端機 |
| 命令 | 指令 |
| 新建 | 新增 |
| 相对路径 | 相對路徑 |
| 打开 | 開啟 |

## 交付计划（一步到位，全 7 语言）

1. 三份 String Catalog 建好，`project.yml` / `Package.swift` 接好本地化配置。
2. AppKit 文案显式包 `String(localized:)`；菜单拼接改占位符格式串（决策 3）。
3. 一次填齐全部 7 种语言译文：`zh-Hans`（源，免翻）+ `en`、`zh-Hant`（繁中独立用词）、`ja`、`de`、`fr`、`es`。
4. 伪本地化（Pseudolanguage）查截断/漏译。
5. 闭环验证：逐一切换系统语言，实测右键菜单、设置页、弹窗、新建文件；重点抽测日/德语序与繁中用词。

## 测试与验证

- **catalog 完整性**：每种语言无「未翻译」状态项。
- **伪本地化**：Xcode Scheme 设 Pseudolanguage，检查文案截断、硬编码遗漏。
- **实机切换**：改系统语言后重启 Finder 扩展（`pluginkit` / 注销登录），验证右键菜单与设置页均切换。
- **占位符换序**：确认日语/德语菜单标题语序正确、品牌名未被翻译。
- **回归**：现有 `EasyContextCoreTests` 全绿；`FileTemplate.displayName` 若被测试引用需同步。

## 非目标（YAGNI）

- 不做应用内语言切换 UI。
- 不本地化 Core 内部错误/日志/注释。
- 不做 RTL（阿拉伯语/希伯来语）布局。
- 不翻译品牌名与用户自定义数据。

## 主要风险

- **FinderSync 扩展本地化不生效**：扩展是独立沙盒 bundle，须确认 catalog 编译进扩展自身 bundle 且 `CFBundleLocalizations` 正确，否则系统不认。闭环验证专门覆盖此点。
- **SPM 资源打包**：`Bundle.module` 在扩展宿主环境下的可用性需实测（验证 `FileTemplate.displayName` 在扩展右键子菜单里正确显示）。

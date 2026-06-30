# Easy Context — 设计文档（实现现状 / as-built）

- 初始设计：2026-06-30
- 本次同步：2026-06-30（按实际实现重写；早期「关沙盒 + App Group」方案已废弃）
- 作者：luyt（与 Claude 共同设计）

> 本文档描述**当前实际架构**。开发过程中因 FinderSync 的真机约束做了多处关键调整，
> 与最初设计差异较大；变更纪要见文末「附录 A：相对初始设计的变更」。

## 1. 背景与目标

用户长期使用 Windows 丰富的右键菜单，转用 macOS 后不适应访达精简的右键菜单。曾购买 EasyNewFile，但更新缓慢、功能不足。本项目自研一款 macOS 应用，**扩展访达（Finder）右键菜单**，覆盖日常高频操作。

定位：**本地自用**，不公证、不上架；**ad-hoc 签名**即可运行，无需 Apple 开发者账号。

## 2. 功能范围（当前）

右键文件/目录时，扩展按配置注入（平铺，新建文件为子菜单）：

- **复制完整路径**
- **复制相对路径**（相对最近 `.git` 根；不在仓库内回退 `~/...`；再不在返回绝对路径）
- **用 \<终端\> 打开终端** ——配置启用且已安装的终端各一项，在目标目录打开
- **用 \<编辑器\> 打开** ——同上，编辑器
- **新建文件 ›** ——子菜单选模板（空白 / .md / .txt / .sh / .json），在目标目录直接创建（默认名「未命名」，重名加序号）
- **外置磁盘**：内置盘与所有 `/Volumes/*` 外置盘均生效

菜单图标：终端/编辑器用各自 App 真图标，内置项用 SF Symbols；支持**黑白/彩色**切换、并适配**深色模式**。

## 3. 总体架构

单个 Xcode 工程（由 **XcodeGen** 从 `project.yml` 生成，`.xcodeproj`/`build/` 不入库），三部分：

### 3.1 EasyContextCore（本地 Swift 包，纯逻辑）
宿主与扩展共享。命令行 `swift test` 驱动 TDD（24 个测试）。含：
- `TargetDirectoryResolver`：选中文件→其所在目录，选中目录→自身。
- `RelativePathResolver`：相对 git 根/家目录/绝对路径。
- `KnownApp` / `KnownApps`：内置终端与编辑器清单（含主流 AI 编辑器 Cursor/Windsurf/Trae/Zed 等、JetBrains 全家桶、Wave/Ghostty 等终端）。
- `AppDetector`：按 `isInstalled` 谓词过滤已安装。
- `FileTemplate` / `UniqueNameResolver`：新建文件模板与重名去重。
- `AppEntry` / `Settings` / `ConfigStore`：配置模型与文件读写（见 §5）。

### 3.2 FinderSync 扩展（EasyContextFinder，沙盒）
- macOS 唯一官方的访达右键菜单扩展机制（`FIFinderSync`）。
- **必须开启 App Sandbox**（pkd 拒绝非沙盒插件——这是早期「关沙盒」方案被推翻的根因）。
- 主类 `FinderSyncExtension`，监控启动卷 + 所有挂载卷（覆盖外置盘），读配置构建菜单、执行动作。

### 3.3 宿主 App（EasyContext，SwiftUI，非沙盒）
- 设置界面（见 §6）。
- 启动时 reconcile 配置、检测扩展是否启用、引导用户启用扩展。

## 4. 签名、沙盒与文件访问

- **签名**：ad-hoc（`CODE_SIGN_IDENTITY="-"`），无需账号；产物对扩展加载已足够。
- **扩展沙盒**：开启。entitlements（`EasyContextFinder/EasyContextFinder.entitlements`）：
  - `com.apple.security.app-sandbox = true`
  - `com.apple.security.files.user-selected.read-write = true`
  - `com.apple.security.temporary-exception.files.absolute-path.read-write = [/Users/, /Volumes/, /private/, /tmp/]`
    —— 本地自用（非上架）下放开常见文件位置，使沙盒扩展能在右键目录打开 App / 新建文件、覆盖外置盘、并读取共享配置。
- **宿主沙盒**：关闭（可自由跑 `pluginkit`、读 `.app` 信息、写配置）。
- **构建命令**（务必这条；`ENABLE_DEBUG_DYLIB=NO` 必须，否则 Debug 的 debug-dylib 桩使扩展无法独立加载）：
  ```bash
  xcodegen generate
  xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug \
    -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES ENABLE_DEBUG_DYLIB=NO build
  ```
- **安装/启用**：拷 `.app` 到 `/Applications` → 运行一次（注册扩展）→ 系统设置「访达扩展」勾选 → 即生效。

## 5. 共享配置

- 路径：**`~/.easy-context/config.json`**。两端用 `getpwuid(getuid())->pw_dir` 取**真实家目录**（沙盒里 `NSHomeDirectory()` 会重定向到容器，故不能用；该路径在 `/Users/` 下，被扩展 entitlement 放行），保证宿主与扩展读同一份。
- Schema（version 2，解码容忍缺字段→回退默认）：
  ```jsonc
  {
    "version": 2,
    "items": { "copyFullPath": true, "copyRelativePath": true, "newFile": true },
    "terminals": [ { "bundleId": "...", "name": "...", "custom": false, "enabled": true } ],
    "editors":   [ /* 同结构 */ ],
    "appearance": { "appIconStyle": "monochrome" }   // monochrome | color
  }
  ```
- **AppEntry**：`bundleId`（唯一键）、`name`、`custom`（内置/自定义）、`enabled`（是否显示）。
- **reconcile**（宿主启动跑）：并入已安装的内置 App（缺失则加，默认 enabled）、去重、排序（内置在前按内置清单顺序、自定义在后保留添加顺序）；保留既有 `enabled`、自定义项、以及被卸载的内置条目。
- **扩展显示**：`enabled && 已安装` 的条目按列表顺序显示；列表为空（配置未初始化）时安全回退为检测到的内置 App。

## 6. 设置界面（宿主）

- 顶部横幅：用 `pluginkit -m -i <扩展 id>` 检测扩展是否启用（行首 `+`=启用）；**未启用时显示橙色横幅**「去启用」（`FIFinderSyncController.showExtensionManagementInterface()` 直开扩展管理）+「重新检测」；App 重新激活时复查。
- 布局：宽窗口（820×507，高:宽≈0.618），上下两部分各两栏。
  - 上半：左「菜单项」（3 个开关，名称左/switch 右）｜右「菜单图标」(黑白/彩色) + 「其他」(打开配置目录 / 访达扩展设置)。
  - 下半：左「终端」｜右「编辑器」——应用列表（图标+名称+switch），底部 `+/-`（`+` 文件选择器添加自定义；`-` 删选中的自定义项，内置不可删）。
  - 列间淡色竖分隔、上下横分隔内缩、列表行无分隔线。
- **自定义添加**：选 `.app` → 读其 bundleId/名称 → 用 `urlsForApplications(toOpen:)` 检测是否声明可打开目录，不支持则警告「可能不支持以目录方式打开」但仍允许添加。

## 7. 关键实现要点（FinderSync 真机约束）

- **线程模型（最易踩坑）**：`menu(for:)` 与菜单点击的动作回调在**后台 XPC 工作线程**运行，**不是主线程**；`init()` 与 NSWorkspace 卷通知在主线程。⚠️ 曾误加 `assert(Thread.isMainThread)` 致每次右键崩溃。由此：跨两者共享的缓存用 `NSRecursiveLock` 加锁（临界区只读写缓存、耗时计算放锁外）；离屏图标渲染用 bitmap-backed `NSGraphicsContext`（不用 `NSImage.lockFocus`）；深浅色判断读全局 `AppleInterfaceStyle`（不用主线程属性 `NSApp.effectiveAppearance`）。
- **打开方式**：沙盒禁止 spawn 进程，故用 `NSWorkspace.open([dir], withApplicationAt:)`（LaunchServices），不用 `Process`/`/usr/bin/open`。
- **菜单项定位**：FinderSync 的 XPC 往返会丢弃 `NSMenuItem.representedObject`，故用 **`tag`** 索引应用列表。
- **新建文件**：扩展不能弹模态窗（NSAlert 抛异常），故改为**模板子菜单 + 直接创建**（无命名弹框，用户自行重命名）。
- **外置磁盘**：单个 `/` 不覆盖外置卷，故监控**所有挂载卷** + 监听挂载/卸载/改名动态刷新。
- **图标深色适配**：FinderSync 把 template 符号栅格化成固定黑色、不随深浅变化，故按当前外观手动给符号着色；App 图标用纯灰度（浅/深色背景下都可辨）。

## 8. 验证

- Core：`cd EasyContextCore && swift test`（24/24）。
- 集成：访达 UI / 扩展加载只能手动验证——右键内置盘与外置盘目录，逐项验证复制路径、打开终端/编辑器、新建文件（各模板、重名、可执行位）、设置实时联动、深浅色图标、未启用横幅。

## 9. 后续可选项（未做）

- **宿主代执行**：让非沙盒宿主代扩展执行任意打开方式（CLI/AppleScript/`open`），以支持「声明不支持目录打开」的 App。
- 正式分发（公证/上架）—— 届时需改回 App Group 共享配置并申请相应 entitlement（很可能需付费账号）。
- PearAI/Void/Aide 等无可靠 bundle id 的 AI 编辑器纳入内置清单（目前靠「+」自定义添加）。

---

## 附录 A：相对初始设计的变更

| 初始设计 | 现状 | 原因 |
|---|---|---|
| 关闭 App Sandbox | 扩展**必须开沙盒** | pkd 拒绝非沙盒 FinderSync 插件 |
| App Group 共享 `UserDefaults` | `~/.easy-context/config.json` 文件 + getpwuid | 无开发者账号；App Group entitlement 难生效 |
| `Process` 跑 `/usr/bin/open -b` | `NSWorkspace.open` | 沙盒禁止 spawn 进程 |
| `OpenCommand`/`ProcessSpec`（Core） | 已移除 | 改用 NSWorkspace 后成死代码 |
| 新建文件 NSAlert 命名弹框 | 模板子菜单直接创建 | 扩展不能弹模态窗 |
| 配置 `showAll` + enabled 列表 | AppEntry 列表 + reconcile | 支持固定/自定义 App、去重排序 |
| 监控根 `/` | 监控所有挂载卷 + 动态刷新 | `/` 不覆盖外置卷 |
| 菜单 `representedObject` 带 bundleId | 改用 `tag` | XPC 往返丢弃 representedObject |
| 手动建 Xcode 工程 | XcodeGen `project.yml` | 可脚本化、可复现、可版本化 |

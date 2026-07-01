# Easy Context

给 macOS **访达（Finder）右键菜单**加上日常高频操作：复制路径、用终端 / 编辑器打开当前目录、新建文件等。灵感来自 EasyNewFile，但更现代、更可配置、支持各类主流终端与 AI 编辑器。

> 纯原生 Swift / SwiftUI + FinderSync 扩展。本地自用，ad-hoc 签名即可运行。

## 截图

| 设置 | 右键菜单 |
|---|---|
| ![设置](docs/screenshots/settings.png) | ![使用](docs/screenshots/usage.png) |

## 功能

- **复制完整路径** / **复制相对路径**（相对最近的 `.git` 仓库根，不在仓库内回退 `~`）
- **用终端打开**当前目录 —— 自动识别 Terminal、iTerm、Warp、Ghostty、kitty、WezTerm、Alacritty、Hyper、Tabby、Rio、Wave、Termius
- **用编辑器打开**当前目录 —— VS Code、Cursor、Windsurf、Trae、Zed、Sublime Text、Nova、BBEdit、Xcode、JetBrains 全家桶（WebStorm / IntelliJ / PyCharm / GoLand / CLion / PhpStorm / RubyMine / Rider / DataGrip / Fleet）、Android Studio 等
- **在终端运行命令**（`用 XX 运行 YY`）—— 一键在**执行终端**里于当前目录运行 AI CLI 等命令（预置 `claude` / `codex`，可自定义增删）
- **新建文件** —— 子菜单选模板（空白 / Markdown / 文本 / Shell / JSON），重名自动加序号，`.sh` 自动加可执行位
- **内置盘 + 外置磁盘**都生效
- **可配置设置界面**：选择菜单显示哪些终端 / 编辑器、管理自定义命令、选执行终端、`+` 自定义添加未识别的 App、菜单图标黑白 / 彩色、深色模式自动适配

## 安装

> 应用为 ad-hoc 签名、**未做 Apple 公证**，首次安装需手动允许一次（详见 DMG 内「安装说明（必读）.txt」）。

1. 打开 `EasyContext.dmg`，把 **EasyContext** 拖到「应用程序」。
2. 首次打开：在「应用程序」里**右键 EasyContext →「打开」**→ 弹窗再点「打开」。
3. 让扩展生效（关键，必做）。打开「终端」执行：
   ```bash
   sudo xattr -dr com.apple.quarantine /Applications/EasyContext.app
   ```
4. 启用扩展：打开 EasyContext，点顶部横幅「去启用」，或
   **系统设置 → 通用 → 登录项与扩展 → 访达扩展 → 勾选 EasyContextFinder**。
5. 在访达里右键任意文件 / 文件夹即可使用。

## 配置

两种方式，读写同一份配置：

- **图形界面**：打开 EasyContext，勾选要显示的 App、调整菜单图标风格等。
- **手改配置文件**：`~/.easy-context/config.json`，修改即时生效（扩展按文件修改时间智能重读）。

配置文件结构：

```jsonc
{
  "version": 3,
  "items": { "copyFullPath": true, "copyRelativePath": true, "newFile": true },
  "terminals": [
    { "bundleId": "com.apple.Terminal", "name": "Terminal", "custom": false, "enabled": true }
  ],
  "editors":  [ /* 同结构 */ ],
  "commands": [                                     // 「用 XX 运行 YY」的命令
    { "id": "…uuid…", "name": "Claude", "command": "claude", "enabled": true }
  ],
  "defaultTerminal": null,                          // 执行终端 bundleId；null=第一个已安装终端
  "terminalTemplates": {},                          // 终端启动模板的“用户覆盖”，空=全用内置
  "appearance": { "appIconStyle": "monochrome" }    // monochrome | color
}
```

- 终端 / 编辑器的 `enabled` 控制**是否在右键菜单显示**；`custom: true` 为用户自行添加的 App。
- 启动时会自动并入新检测到的内置 App、去重并排序（内置在前、自定义在后），并保留你的开关与自定义项。

### 在终端运行命令

- 右键菜单出现 `用 <执行终端> 运行 <命令名>`（如 `用 Terminal 运行 Claude`），在**当前目录**打开终端并运行该命令。
- **执行终端 ≠ 菜单显示**：执行终端是「命令在哪跑」，只看**装没装**，与「菜单显示的终端」开关无关；设置界面「执行终端」下拉列出全部已安装终端，`null` 时取第一个已安装终端（系统 Terminal 兜底）。
- **PATH**：GUI 进程 PATH 精简，`-e` 型终端（Ghostty/kitty/WezTerm/Alacritty）经用户登录 shell `$EC_SHELL -lic <cmd>` 运行，确保能找到 `~/.local/bin` 等里的 `claude`/`codex`。
- **自定义启动模板**：`terminalTemplates` 只存**覆盖**（空 = 用内置）。想改某终端：参照配置目录里自动生成的 **`terminal-templates.reference.json`**（列出全部内置模板与 bundleId），把对应条目复制到 `terminalTemplates` 修改。占位符 `{dir}`/`{cmd}` 会替换为 `"$EC_DIR"`/`"$EC_CMD"`（值只走环境变量，勿自行加引号），可用 `$EC_SHELL`。
- ⚠️ **Ghostty 作执行终端**：Ghostty 对「外部经 `-e` 执行命令」**每次弹安全确认**且官方不提供关闭（既定安全设计）。建议执行终端用 **Terminal / iTerm**（AppleScript，单窗口、无弹框）——默认即 Terminal。

## 从源码构建

依赖：完整版 **Xcode**、[**XcodeGen**](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
# 生成工程并构建（Debug）
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES ENABLE_DEBUG_DYLIB=NO build

# 纯逻辑层单元测试
cd EasyContextCore && swift test

# 打包成带样式的分发 DMG（自动建 venv 装 dmgbuild）
./scripts/build-dmg.sh   # 产物：dist/EasyContext.dmg
```

## 架构

- **EasyContextCore**（本地 Swift 包）：纯逻辑（路径解析、App 检测、配置模型 / reconcile、文件模板…），命令行 `swift test` 驱动 TDD。
- **EasyContextFinder**（FinderSync 扩展，沙盒）：注入右键菜单、执行动作。
- **EasyContext**（SwiftUI 宿主，非沙盒）：设置界面、引导启用扩展。
- 宿主与扩展通过共享文件 `~/.easy-context/config.json` 交换配置。

详见 [设计文档](docs/superpowers/specs/2026-06-30-easy-context-design.md)（含相对初始设计的关键变更）。

## FinderSync 开发要点（贡献者须知）

这类扩展有不少非显而易见的约束，踩过的坑记录在此，避免重蹈：

- **`menu(for:)` 与菜单点击的动作回调运行在后台 XPC 工作线程，不是主线程**；而 `init()` 与 NSWorkspace 卷挂载/卸载通知在主线程。⚠️ 曾因误加 `assert(Thread.isMainThread)` 到 `menu(for:)`、错误假设它在主线程，导致每次右键扩展崩溃。由此衍生：
  - 跨「工作线程菜单构建」与「主线程卷通知」共享的缓存**必须加锁**（本项目用 `NSRecursiveLock`，临界区只读写缓存、把读盘/渲染等耗时操作放在锁外）。
  - 离屏图标绘制用 **bitmap-backed `NSGraphicsContext`**，不要用 `NSImage.lockFocus`（主线程取向的 API，在工作线程属未受支持路径，会偶发失败/崩溃）。
  - 读系统深浅色用全局 **`AppleInterfaceStyle`**，不要用 `NSApp.effectiveAppearance`（主线程属性，工作线程取值不可靠）。
- **扩展必须开启 App Sandbox**（pkd 拒绝非沙盒插件）；本地自用靠 `temporary-exception` entitlement 放行 `/Users//Volumes/` 等文件访问。
- **菜单项的 `representedObject` 会在 XPC 往返中丢失**，故用 `tag` 索引应用列表。
- **打开 App 用 `NSWorkspace.open`**（沙盒禁止 spawn 进程，不能用 `Process`/`open`）；**新建文件用子菜单**直接创建（扩展弹模态 `NSAlert` 会抛异常）。
- **监控所有挂载卷**（单个 `/` 不覆盖 `/Volumes/*` 外置盘），并监听挂载/卸载/改名动态刷新。
- **Debug 构建须 `ENABLE_DEBUG_DYLIB=NO`**，否则 debug-dylib 桩会让扩展无法独立加载。

## 已知限制

- **分发**：ad-hoc 签名分发给他人需对方手动允许 + 清除 quarantine。要做到「下载即用、无警告」，需 **Apple Developer ID 证书 + 公证（notarization）**（付费账号）。
- 部分小众 AI 编辑器（PearAI / Void 等）暂无可靠 bundle id，未进内置清单，可用设置界面的 `+` 自行添加。
- **Ghostty 作执行终端**每次运行命令会弹 Ghostty 自带的安全确认（官方设计，无法关闭）；想免弹框请把执行终端设为 Terminal / iTerm。

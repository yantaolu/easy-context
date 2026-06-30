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
- **新建文件** —— 子菜单选模板（空白 / Markdown / 文本 / Shell / JSON），重名自动加序号，`.sh` 自动加可执行位
- **内置盘 + 外置磁盘**都生效
- **可配置设置界面**：选择显示哪些终端 / 编辑器、`+` 自定义添加未识别的 App、菜单图标黑白 / 彩色、深色模式自动适配

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
  "version": 2,
  "items": { "copyFullPath": true, "copyRelativePath": true, "newFile": true },
  "terminals": [
    { "bundleId": "com.apple.Terminal", "name": "Terminal", "custom": false, "enabled": true }
  ],
  "editors":  [ /* 同结构 */ ],
  "appearance": { "appIconStyle": "monochrome" }   // monochrome | color
}
```

- `enabled` 控制是否在右键菜单显示；`custom: true` 为用户自行添加的 App。
- 启动时会自动并入新检测到的内置 App、去重并排序（内置在前、自定义在后），并保留你的开关与自定义项。

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

## 已知限制

- **分发**：ad-hoc 签名分发给他人需对方手动允许 + 清除 quarantine。要做到「下载即用、无警告」，需 **Apple Developer ID 证书 + 公证（notarization）**（付费账号）。
- 部分小众 AI 编辑器（PearAI / Void 等）暂无可靠 bundle id，未进内置清单，可用设置界面的 `+` 自行添加。

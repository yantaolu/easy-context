# Easy Context

给 macOS **访达（Finder）右键菜单**加上日常高频操作：复制路径、用终端 / 编辑器打开当前目录、新建文件等。灵感来自 EasyNewFile，但更现代、更可配置、支持各类主流终端与 AI 编辑器。

> 纯原生 Swift / SwiftUI + FinderSync 扩展。本地自用，ad-hoc 签名即可运行。

## 截图

| 设置 | 右键菜单 |
|---|---|
| ![设置](docs/screenshots/settings.png) | ![使用](docs/screenshots/usage.png) |

## 功能

- **复制完整路径** / **复制相对路径**（相对最近的 `.git` 仓库根，不在仓库内回退 `~`）
- **用终端打开**当前目录 —— 自动识别 Terminal、iTerm、Warp、Otty、Ghostty、cmux、Muxy、kitty、WezTerm、Alacritty、Hyper、Tabby、Rio、Wave、Termius
- **用编辑器打开**当前目录 —— VS Code、VSCodium、Cursor、Trae、Devin（原 Windsurf）、CodeBuddy、Zed、Sublime Text、Nova、BBEdit、TextMate、MacVim、Emacs、Xcode、JetBrains 全家桶（WebStorm / IntelliJ IDEA〔含 CE〕/ PyCharm〔含 CE〕/ GoLand / CLion / PhpStorm / RubyMine / Rider / DataGrip / Fleet）、Android Studio 等
- **在终端运行命令**（`用 XX 运行 YY`）—— 一键在**执行终端**里于当前目录运行 AI CLI 等命令（预置 `claude` / `codex`，可自定义增删）
- **新建文件** —— 子菜单选模板（Markdown / 文本 / Shell / JSON），弹**命名面板**输入文件名（预选基名、保留扩展名；重名自动加序号、`.sh` 自动加可执行位），创建后在 Finder 中选中
- **多语言支持** —— 自动跟随系统语言切换，支持简体中文、English、繁體中文、日本語、Deutsch、Français、Español 7 种语言
- **内置盘 + 外置磁盘**都生效
- **可配置设置界面**：选择菜单显示哪些终端 / 编辑器、管理自定义命令、选执行终端、`+` 自定义添加未识别的 App、菜单图标黑白 / 彩色、深色模式自动适配
- **版本与更新提醒**：设置窗口底部显示版本号和刷新图标，点击后以弹窗告知检查结果；发现新版可前往 GitHub 下载，不自动下载安装。

多选目标规则：复制完整路径 / 相对路径会复制所有选中项；打开终端 / 打开编辑器会把目录取自身、文件取父目录后按路径去重，并打开这些目录；运行命令 / 新建文件是一次性动作，使用去重后的第一个目录。

## 安装

从 [GitHub Releases](https://github.com/yantaolu/easy-context/releases) 下载与 Mac 芯片对应的安装包：Apple Silicon 选择 `EasyContext-<版本>-macOS-arm64.pkg`，Intel 选择 `EasyContext-<版本>-macOS-x86_64.pkg`。`.pkg` 本身未签名；其中的 App 使用 ad-hoc 签名、**未做 Apple 公证**，首次打开安装包需手动允许一次（详见 [`packaging/安装说明.txt`](packaging/安装说明.txt)）。

1. **右键**点与你的 Mac 芯片对应的 `.pkg` →「打开」→ 弹窗再点「打开」（不签名安装包直接双击会被拦，用右键打开这一次即可）。
2. 按安装向导点「继续 / 安装」，输入密码授权装到「应用程序」。装完 App 会自动启动；重装 / 更新时安装程序会**自动关闭旧版本**，无需手动退出、也不会再报「正在使用中」。
3. 启用扩展：打开 EasyContext，点顶部横幅「去启用」，或
   **系统设置 → 通用 → 登录项与扩展 → 访达扩展 → 勾选 EasyContextFinder**。
4. 在访达里右键任意文件 / 文件夹即可使用。

> pkg 装出来的 App 不带隔离标记，**无需再执行 `sudo xattr -dr com.apple.quarantine`**。命令行安装示例：`sudo installer -pkg EasyContext-<版本>-macOS-arm64.pkg -target /`（Intel 请替换为 `x86_64`）。

### 发布版本

`project.yml` 的 `MARKETING_VERSION`（严格 `X.Y.Z`）和 `CURRENT_PROJECT_VERSION`（正整数构建号）是唯一的构建版本来源。宿主、Finder 扩展、本地安装包和 CI 使用同一对值；客户端显示安装包内实际的版本，不读取仓库文件。配置文件中的 `"version": 3` 是配置格式版本，与产品版本无关。

版本规则：修复使用 patch（例如 `1.0.2 → 1.0.3`），兼容的新功能使用 minor（例如 `1.0.2 → 1.1.0`），不兼容变化使用 major。每次准备新版本时构建号递增一次；构建或重跑 CI 不会自行改变版本。

维护者发布流程（以下 `1.1.0` 仅为示例）：

```bash
# 1. 查看当前版本，预览下一版本；预览不写文件
./scripts/version.sh
./scripts/prepare-release.sh --dry-run 1.1.0

# 2. 更新 project.yml 中的版本和构建号；不会提交、打标签或推送
./scripts/prepare-release.sh 1.1.0
git diff -- project.yml

# 3. 验证脚本与核心逻辑，再按需要构建并测试安装包
./scripts/test-version.sh
swift test --package-path EasyContextCore \
  --skip CommandsTests/test_builtin_muxy_routesCommandToPaneCreatedForNewTab
TARGET_ARCH=arm64 ./scripts/build-pkg.sh

# 4. 审查并提交本次功能与版本改动，合入 master，等待分支 CI 成功
# 请按实际改动选择 git add 的文件，不要遗漏待发布的功能代码。

# 5. 在已合入 master 的目标提交上校验、打标签、推送
./scripts/version.sh --check-tag v1.1.0
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

GitHub Actions 会校验标签版本与工程一致、标签提交可从 `origin/master` 到达，运行测试，分别构建 `arm64` / `x86_64` `.pkg`，生成 SHA-256 校验文件，再创建同名 Release 并标为 Latest。只有两个架构都成功，才公开发布。Release Notes 继续由 GitHub 生成，不引入 changelog 工具或额外语言依赖。

已发布版本不得挪动标签或替换产物；修复后准备下一个版本。准备脚本检查本地已有标签，操作前应确保本地标签与远端同步。发布失败时先查看 Actions 日志，不要通过强推标签绕过校验。

Release 提供的 `.pkg` 未签名，其中 App 为 ad-hoc 签名且**未公证**；这不是 App Store 或 Developer ID 签名发布，下载者仍可能看到 macOS 安全提示。

### 客户端检查更新

- 设置窗口保持原来的 800×494 尺寸。底部原「其他」标题替换为版本号，悬停可查看完整版本与构建号；点击紧随其后的刷新图标才查询本仓库 GitHub Latest Release，检查期间图标显示忙碌状态并禁止重复点击。
- 只识别严格 `vX.Y.Z` 的稳定发布，并检查两种架构的安装包及校验文件是否齐全。远端版本必须高于本机版本才提醒，不会建议降级。
- 检查完成后以弹窗显示「已是最新版本」「发现新版本」或「检查失败」。新版本弹窗提供「前往 GitHub 下载」和取消按钮；下载按钮用浏览器打开本仓库 Release 页面，由你选择芯片架构并手动安装。
- 不显示常驻的更新开关、说明或状态文字，不在打开设置时自动联网或弹窗。关闭设置窗口会撤销本次结果的弹窗呈现，晚到的网络响应不会重新打开窗口或抢焦点。
- 超时、网络错误和 GitHub 限流会明确提示，不把失败当作「已是最新版本」；服务端要求等待时，手动点击也不能绕过限流。
- 检查缓存保存在宿主 App 的 `UserDefaults`，不写入共享 `config.json`。旧预览版的自动检查偏好不再触发查询。请求不携带目录路径、命令、配置内容或身份令牌；GitHub 仍会正常收到连接来源 IP 等网络信息。
- **只有点击刷新图标才会检查更新**，不自动下载、不申请管理员权限、不强制更新。已发布的旧版 `1.0.2` 本身没有这项功能，需要先手动安装包含此功能的新版本。

## 配置

两种方式，读写同一份配置：

- **图形界面**：打开 EasyContext，勾选要显示的 App、调整菜单图标风格等。
- **手改配置文件**：`~/.easy-context/config.json`，修改即时生效——扩展按文件修改时间智能重读；宿主设置窗在切回（App 重新激活）时也会自动重读外部改动。

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
  "defaultTerminal": null,                          // 执行终端 bundleId；null=第一个可用终端
  "terminalTemplates": {},                          // 终端启动模板的“用户覆盖”，空=全用内置
  "appearance": { "appIconStyle": "monochrome" }    // monochrome | color
}
```

- 终端 / 编辑器的 `enabled` 控制**是否在右键菜单显示**；`custom: true` 为用户自行添加的 App。
- 启动时、以及每次切回设置窗（App 重新激活）时，都会自动并入新检测到的内置 App、去重并排序（内置在前、自定义在后），并保留你的开关与自定义项——运行期新装的内置 App 切回设置窗即出现，**无需重启**。
- 设置列表只展示**已安装**的 App；卸载后条目仍保留在配置里（开关状态不丢、重装自动回来），只是不在列表显示。

### 在终端运行命令

- 右键菜单出现 `用 <执行终端> 运行 <命令名>`（如 `用 Terminal 运行 Claude`），在**当前目录**打开终端并运行该命令。多选跨目录时只作用于去重后的**第一个目录**（一个终端窗口）。
- **执行终端 ≠ 菜单显示**：执行终端是「命令在哪跑」，与「菜单显示的终端」开关无关，条件是**已安装且有启动模板**——内置模板覆盖 Terminal / iTerm / Ghostty / cmux / Otty / Muxy / kitty / WezTerm / Alacritty；其余（Warp、Hyper 等）需在 `terminalTemplates` 自行添加模板后才会进入候选。设置界面「执行终端」下拉即列出这些可用终端，`defaultTerminal` 为 `null` 时取第一个（系统 Terminal 兜底）。
- **PATH**：GUI 进程 PATH 精简，`-e` 型终端（kitty/WezTerm/Alacritty）经用户登录 shell `$EC_SHELL -lic <cmd>` 运行，确保能找到 `~/.local/bin` 等里的 `claude`/`codex`。Terminal/iTerm/Ghostty/cmux 用 AppleScript 把命令输入交互 shell，PATH 天然正确；Otty 使用其官方 CLI。
- **自定义启动模板**：`terminalTemplates` 只存**覆盖**（空 = 用内置）。想改某终端：参照配置目录里自动生成的 **`terminal-templates.reference.json`**（列出全部内置模板与 bundleId），把对应条目复制到 `terminalTemplates` 修改。占位符 `{dir}`/`{cmd}` 会替换为 `"$EC_DIR"`/`"$EC_CMD"`（勿自行加引号），可用 `$EC_SHELL`。AppleScript 模板不得用 `system attribute` 读取 `EC_DIR`/`EC_CMD`，该方式可能在某些区域设置下损坏 Unicode；请照新版内置模板，用 `on run argv` 并以 `-- "$EC_DIR" "$EC_CMD"` 传入两个参数。**旧的用户覆盖不会自动迁移**；若覆盖了 Terminal / iTerm / Ghostty / cmux，删除对应覆盖即可恢复使用新版内置模板。
- **Ghostty / cmux / Terminal / iTerm** 用 AppleScript 运行命令（把命令输入交互 shell，非 `-e` 执行）：无「Allow execute」弹框、PATH 正确；仅**首次**需一次性授权「EasyContext 控制 <终端>」（macOS 自动化权限）。Ghostty 需 1.3.0+；cmux 使用其官方 Scripting Dictionary 新建 workspace 并向 focused terminal 发送命令。
- **Otty** 使用 App 内置的官方 CLI（按 Otty 1.4.1 API）：已有窗口时原子地新建一个 tab，再以 `--cwd` / `--command` 启动命令；没有窗口时创建窗口。它不会向当前正在交互的终端 pane 输入文本。请使用提供 `otty-cli`、`window show current`、`tab new` 和 `open` 的 Otty 1.4.1 或兼容版本。
- **Muxy** 使用官方 CLI：先在 Muxy 菜单执行 **Muxy → Install CLI**。Easy Context 会先用 `muxy <目录>` 打开或选中项目；首次打开时复用 Muxy 自动创建的初始终端 tab，项目已打开时只新建一个命令 tab，然后发送命令并回车。Muxy 冷启动时会等待其本地控制服务就绪。

## 从源码构建

依赖：完整版 **Xcode**、[**XcodeGen**](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
# 生成工程并构建（Debug）
xcodegen generate
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug \
  -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES ENABLE_DEBUG_DYLIB=NO build

# 纯逻辑层单元测试
swift test --package-path EasyContextCore

# 打包成 .pkg，版本自动读取 project.yml
./scripts/build-pkg.sh
# 分架构产物：设置 TARGET_ARCH=arm64 或 TARGET_ARCH=x86_64
TARGET_ARCH=arm64 ./scripts/build-pkg.sh
# 产物：dist/EasyContext-<工程版本>-macOS-arm64.pkg
# TARGET_ARCH=x86_64 时产物为 EasyContext-<工程版本>-macOS-x86_64.pkg
# 省略 TARGET_ARCH 仍可在本地构建 universal 包

# 同一产品版本下，本地改代码后需要重新安装测试时，明确递增构建号
./scripts/prepare-release.sh --build-only
TARGET_ARCH=arm64 ./scripts/build-pkg.sh
```

不再使用 `VERSION=... BUILD_NUMBER=...` 覆盖出另一套版本；如果传入值与工程不同，构建会拒绝。`--build-only` 只用于本地测试或正式发布前的构建准备，不会让客户端按 build number 提醒更新，也不能用于替换已发布的同版本 Release。新版本安装测试前，请先准备高于已安装版本的版本号或构建号，避免 macOS Installer 保留已有新版本。

安装包保留 macOS 原有的版本检查，安装后还会验证宿主与扩展的实际版本、构建号及可执行文件 SHA-256。若系统跳过 payload 或文件不匹配，会明确报错，不再仅以「App 文件存在」判断成功；此检查不等于开发者签名认证，也不保证自动回滚。遇到错误请查看 Installer 日志，并使用正确的新版本重新安装。安装后的辅助步骤在非当前启动卷上只校验目标卷，不启动 App 或刷新当前会话的 Finder。

## 架构

- **EasyContextCore**（本地 Swift 包）：纯逻辑（路径解析、App 检测、配置模型 / reconcile、文件模板…），命令行 `swift test` 驱动 TDD。
- **EasyContextFinder**（FinderSync 扩展，沙盒）：注入右键菜单、执行动作。
- **EasyContext**（AppKit 宿主 + SwiftUI 设置界面，非沙盒）：后台代理型 App，手动管窗，处理设置界面、引导启用扩展、执行命令 / 新建文件。
- 宿主与扩展通过共享文件 `~/.easy-context/config.json` 交换配置。

## FinderSync 开发要点（贡献者须知）

这类扩展有不少非显而易见的约束，踩过的坑记录在此，避免重蹈：

- **`menu(for:)` 与菜单点击的动作回调运行在后台 XPC 工作线程，不是主线程**；而 `init()` 与 NSWorkspace 卷挂载/卸载通知在主线程。⚠️ 曾因误加 `assert(Thread.isMainThread)` 到 `menu(for:)`、错误假设它在主线程，导致每次右键扩展崩溃。由此衍生：
  - 跨「工作线程菜单构建」与「主线程卷通知」共享的缓存**必须加锁**（本项目用 `NSLock`，临界区只读写缓存、把读盘/渲染等耗时操作放在锁外；非递归锁，临界区内不得调用其它加锁方法）。
  - 离屏图标绘制用 **bitmap-backed `NSGraphicsContext`**，不要用 `NSImage.lockFocus`（主线程取向的 API，在工作线程属未受支持路径，会偶发失败/崩溃）。
  - 读系统深浅色：手动深浅色模式读全局 **`AppleInterfaceStyle`**（线程安全）；「自动切换」外观下该键不跟随时段翻转，需 `main.sync` 跳主线程读 `NSApp.effectiveAppearance`（主线程属性，工作线程直接取不可靠）。⚠️ 勿在持缓存锁时调用，否则与主线程等锁形成死锁环。
- **扩展必须开启 App Sandbox**（pkd 拒绝非沙盒插件）；本地自用靠 `temporary-exception` entitlement：普通用户目录、外置卷和临时目录仅临时只读，只有 `~/.easy-context/` 为共享配置 / IPC token 保留 home-relative 读写。
- **菜单项的 `representedObject` 会在 XPC 往返中丢失**，故用 `tag` 索引应用列表。
- **打开 App 用 `NSWorkspace.open`**（沙盒禁止 spawn 进程，不能用 `Process`/`open`）；**新建文件用子菜单**选模板、点选后交宿主弹命名面板创建（扩展弹模态 UI 会抛异常）。
- **监控所有挂载卷**（单个 `/` 不覆盖 `/Volumes/*` 外置盘），并监听挂载/卸载/改名动态刷新。
- **Debug 构建须 `ENABLE_DEBUG_DYLIB=NO`**，否则 debug-dylib 桩会让扩展无法独立加载。

## 已知限制

- **分发**：从 GitHub Releases 按芯片架构下载 `arm64` 或 `x86_64` `.pkg`（`scripts/build-pkg.sh` 构建）——安装出来的 App 不带 quarantine、无需手动清理；安装器会自动关闭正在运行的旧 App、启动宿主并重启 Finder，以立即挂接新版扩展。扩展注册或刷新等辅助步骤失败时会记录警告，但不会回滚已经安装的 App。`.pkg` 未签名，其中的 App 为 ad-hoc 签名、**未公证**，首次打开仍需右键→打开放行一次；要做到「双击即装、全程零提示」，需 **Apple Developer ID 证书 + 公证（notarization）**（付费账号，详见 `scripts/build-pkg.sh` 顶部注释）。
- 部分小众 AI 编辑器（PearAI / Void 等）暂无可靠 bundle id，未进内置清单，可用设置界面的 `+` 自行添加。
- **在终端运行命令 / 新建文件**由宿主 App 处理（后台代理，无 Dock 图标；双击 App 才显示配置窗）：首次用 AppleScript 型终端（Terminal / iTerm / Ghostty / cmux）运行命令时，会弹一次性「控制终端」的自动化授权；Otty 的官方 CLI 路径不需要该自动化授权。
- Warp、Hyper、Tabby、Rio、Wave、Termius 暂无内置启动模板：可在菜单里**打开目录**，但不能作为**执行终端**运行命令，除非在设置的「Templates…」编辑器（或 `terminalTemplates`）里添加模板。
- **外置磁盘在访达侧栏的图标会显示为 EasyContext 的图标**：这是 FinderSync 监控卷根目录（为提供外置盘右键菜单）的系统机制性副作用，与 Dropbox 文件夹在侧栏显示 Dropbox 图标同理，仅影响侧栏显示、不影响磁盘本身；扩展停用后图标即恢复。
- 覆盖安装（升级）时安装器会自动启动宿主并重启访达，以立即挂接新版扩展；扩展注册或刷新失败会记录警告，不会回滚已安装的 App，右键菜单可能需要手动重新启用或等待系统重新扫描注册插件。

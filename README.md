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

版本规则：修复使用 patch，兼容的新功能使用 minor，不兼容变化使用 major。build 是持续递增的候选构建编号，**产品版本升级也不重置，且不是编译次数**：只有 `prepare` 和 `next-build` 会增加它，预览、正式构建和重跑 CI 都不会自动增号。已为某个版本执行过 `prepare`，就不必再次准备同一版本；后续修改需要新的安装测试候选时，使用 `next-build`。

日常只使用 `scripts/release.sh` 入口。原 `version.sh`、`prepare-release.sh` 已合并移除；`build-pkg.sh` 为本地与 CI 共用的底层构建实现，`version-lib.sh` 为内部校验函数，`scripts/lib/publish-release.sh` 仅供发布工作流调用。

下表中的 `1.1.1` 是示例版本；准备新版本时，必须高于当前产品版本和本地已有稳定标签。

| 命令 | 作用 | 产品版本 | build | 构建、联网及 Git 影响 |
|---|---|---|---|---|
| `./scripts/release.sh show` | 显示版本和 build | 不变 | 不变 | 只读本地版本文件 |
| `./scripts/release.sh show --version` | 只输出产品版本 | 不变 | 不变 | 只读本地版本文件 |
| `./scripts/release.sh show --build` | 只输出 build | 不变 | 不变 | 只读本地版本文件 |
| `./scripts/release.sh prepare 1.1.1 --dry-run` | 校验并显示下一版计划 | 不变 | 不变 | 读取本地标签；不构建、不联网 |
| `./scripts/release.sh prepare 1.1.1` | 准备新产品版本 | 改为指定的新版本 | 加 1 | 修改 `project.yml`，读取本地标签；不构建、不联网 |
| `./scripts/release.sh next-build --dry-run` | 显示下一候选 build | 不变 | 不变 | 只读本地版本文件；不构建、不联网 |
| `./scripts/release.sh next-build` | 准备同版本的新候选 | 不变 | 加 1 | 修改 `project.yml`；不构建、不联网 |
| `./scripts/release.sh preview` | 构建本机架构预览包 | 不变 | 不变 | 先清空 `dist`，再生成工程、编译并打包；构建工具可能联网解析依赖，不推送、不安装 |
| `./scripts/release.sh preview --arch universal` | 显式选择预览架构；也可填 `arm64` 或 `x86_64` | 不变 | 不变 | 与默认预览相同，仅改变目标架构 |
| `./scripts/release.sh check v1.1.1` | 完整发布前检查 | 不变 | 不变 | fetch 远端 master/标签并查询 GitHub CI；不构建、不创建标签 |
| `./scripts/release.sh check-tag v1.1.1` | 仅检查严格标签格式与源码版本一致 | 不变 | 不变 | 只读本地文件；允许历史版本重跑，不替代 `check` |

这些命令均不会自动提交、推送或安装。`prepare`、`next-build` 与打包共用仓库锁，在读取待修改或构建的版本前取得锁；同一工作目录已有任务时，新任务会直接拒绝，不增号、不清理对方的输出。请等上一任务完成后重试，构建过程中也不要手动修改版本文件或切换源码；锁不能约束编辑器和外部工具。

**构建前会清空 `dist`，不归档、不保留旧包。** 预览和底层正式打包均如此，包括其中的旧预览目录、隐藏文件和手动放入的文件；需要保留的内容请提前移到 `dist` 外。若后续构建失败，旧产物也不会恢复。本地连续构建 arm64、x86_64 时只保留最后一次结果；需要同时保留两个独立包，请先将第一份包及校验文件复制到 `dist` 外，再构建第二份。GitHub 双架构 jobs 使用独立工作目录，不会互相清理。

维护者按以下顺序发布；所有命令在仓库根目录执行。

1. **准备环境与版本。** 本机需要 macOS、完整版 Xcode（含 Swift 和命令行工具）、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、Git、jq、curl；构建工具须在 PATH 中可用。XcodeGen 可用 `brew install xcodegen` 安装。完整 `check` 还需要访问 GitHub；使用公开 API，无需登录 gh。开始新一版前同步远端标签并查看版本：

   ```bash
   git fetch origin master --tags
   ./scripts/release.sh show
   ./scripts/release.sh prepare 1.1.1 --dry-run
   ./scripts/release.sh prepare 1.1.1
   git diff -- project.yml
   ```

   如果 `show` 已是计划发布的 `1.1.1`，跳过两条 `prepare` 命令，保留当前候选继续测试。不要为了重新编译而重复增号。

2. **测试、预览并手动安装验收。** 先运行与 CI 一致的检查，再构建预览；`preview` 最后输出的路径就是本次安装包。按[安装说明](#安装)手动打开该包，确认设置中的版本/build、Finder 扩展及本次修改的功能。构建成功不等于完成安装验收。

   ```bash
   ./scripts/test-version.sh
   ./scripts/test-publish.sh
   swift test --package-path EasyContextCore \
     --skip CommandsTests/test_builtin_muxy_routesCommandToPaneCreatedForNewTab
   ./scripts/release.sh preview
   ```

   验收后又改了代码、需要区分下一次覆盖安装候选时，依次运行 `./scripts/release.sh next-build --dry-run`、`./scripts/release.sh next-build`，然后重做本步。架构选择和预览包与正式包的关系见[从源码构建](#从源码构建)。

3. **精确暂存、审查并提交。** `git diff` 检查工作区，`git diff --cached` 检查已暂存内容。下面使用交互暂存逐块选择版本和代码改动；新增文件不会出现在 `git add -p` 中，应按 `git status --short` 显示的实际完整路径单独暂存。提交前确保暂存区只包含本次发布内容，且没有遗漏刚验收的未暂存修改。

   ```bash
   git status --short
   git diff
   git add -p -- project.yml EasyContext EasyContextFinder EasyContextCore scripts .github/workflows packaging README.md
   git diff --cached --check
   git diff --cached
   git status --short
   git commit -m "Prepare release 1.1.1"
   ```

4. **合入 master，等待对应提交的 CI。** 若上一步就在本地 `master`，确认分支后执行 `git push origin master`。若在功能分支，通过 PR 合并，再在工作区干净时同步本地 master：

   ```bash
   git switch master
   git pull --ff-only origin master
   git rev-parse HEAD
   ```

   在 Actions 中确认这个完整 SHA 对应的 **master push CI** 成功；PR 检查成功不能替代合并后该提交的 CI。推送 master 只运行 CI，不创建 GitHub Release。

5. **检查通过后立即创建附注标签并推送。** 以下命令用 `&&` 连接，前一步失败就不会继续。在检查与打标签之间不要切换提交、修改源码或增号；如有变化，重新测试、提交并等待对应 CI。

   ```bash
   ./scripts/release.sh check v1.1.1 &&
     git tag -a v1.1.1 -m "Release v1.1.1" &&
     git push origin refs/tags/v1.1.1
   ```

   `check` 要求工作区、暂存区和未跟踪文件均干净，版本文件已提交；它同步远端 master/标签，检查 HEAD 可从 `origin/master` 到达、标签无冲突，并验证同一 SHA 最近的 master push CI。网络失败、限流或 CI 未成功都会停止。**推送版本标签才触发 Release 工作流**。

6. **检查公开附件并完成正式包验收。** Release 成功后应有四个附件：`EasyContext-1.1.1-macOS-arm64.pkg`、同名 `.pkg.sha256`，以及 `x86_64` 对应的包和校验文件。将四个附件下载到同一目录，在该下载目录中执行：

   ```bash
   shasum -a 256 -c EasyContext-1.1.1-macOS-arm64.pkg.sha256
   shasum -a 256 -c EasyContext-1.1.1-macOS-x86_64.pkg.sha256
   ```

   两项均应显示 `OK`。随后手动安装与本机芯片匹配的正式包，确认版本/build、Finder 菜单和更新检查；条件允许时在另一架构的 Mac 上也验收。不要把本地预览包当作已发布附件。

GitHub Actions 会校验标签版本与工程一致、标签提交可从 `origin/master` 到达，运行测试，分别构建 `arm64` / `x86_64` `.pkg` 和 SHA-256 校验文件。只有两个架构和全部附件校验都成功，才公开发布。发布阶段跨标签互斥并启用多任务排队，公开前再次核对远端标签提交；设置 Latest 前要求当前版本确实出现在公开稳定列表中，再按数字版本比较，较旧版本不会抢占 Latest。列表异常或遗漏当前版本会停止，不会误报成功。Release Notes 继续由 GitHub 生成，不引入额外发版框架或语言运行环境。

**发布失败与恢复：** 工作流创建的草稿在正文中记录隐藏的来源标记（仓库、版本标签、提交、build、附件哈希和大小）。在 Actions 中重跑失败的 jobs、复用原始构建 artifacts，可验证并跳过已上传的正确附件，仅续传缺失项；附件或来源冲突会明确停止，不覆盖或删除。重新运行全部 jobs 可能生成字节不同的 pkg，不能当作原草稿的续传产物；此时不要通过修改标记、替换附件或强推标签绕过校验。构建 artifacts 仅保留 7 天，过期或冲突需人工核查。

同一来源的已公开 Release 重跑时，先识别发布状态，跳过 Actions 构建附件下载，直接验证远端原有附件而不替换，再继续完成此前失败的 Latest 设置；因此这条恢复路径不依赖 7 天的构建附件保留期。不存在的 Release 或草稿仍必须下载原始构建附件，下载失败不会绕过校验。识别状态和实际执行时都会重新验证，期间状态变化会停止或按重新验证的状态处理。历史没有来源标记的 Release、人工创建的未知草稿不会自动接管。已发布版本不得挪动标签或替换产物；内容修复应准备下一个版本。互斥只约束本工作流，维护者仍应避免同时手工编辑发布状态；排队、人工取消或平台失败后请检查 Actions 状态，必要时重跑。

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

# 与 CI 一致，跳过会操作真实 Muxy 终端的集成测试
swift test --package-path EasyContextCore \
  --skip CommandsTests/test_builtin_muxy_routesCommandToPaneCreatedForNewTab
```

需要安装测试时使用 `./scripts/release.sh preview`，默认本机架构；`--arch` 可选 `arm64`、`x86_64` 或 `universal`。它只构建，安装需手动执行；源码 ZIP 不含 `.git` 也可预览。版本命令的差异、候选迭代与完整发版步骤统一见[发布版本](#发布版本)。

每次打包先取得共享锁，再读取和校验版本；全部参数、版本和架构校验通过后，清空项目 `dist` 的内容，再开始构建，不建立归档。清理在已确认的目标目录内使用相对路径执行，避免通过被替换的 `dist` 路径删除目录外的文件。预览包和校验文件写入 `dist/preview/` 下带版本、build、架构及独立构建目录的路径，文件名含 `preview`；正常成功后只保留本次构建的产物。它构建当前工作区（包括未暂存内容），不是暂存区；有暂存内容时会提醒。预览与正式包使用相同 Release 编译配置、Bundle ID 和配置目录，不能并存，安装预览会替换已安装应用。流水线从标签提交重新构建，不承诺与本机预览逐字节相同。

每次预览使用独立的 DerivedData，结束后清理本次编译中间文件，仅保留包和校验文件；因此重复预览不复用上一次的增量构建结果，耗时可能增加。同一工作目录已有版本调整或打包任务时，新任务会直接拒绝，不清空对方的输出；`dist` 根是符号链接或非目录时也会拒绝。若任务异常终止留下 `.build-pkg.lock`，应先确认没有版本调整或构建仍在运行，再人工处理锁，不能盲目删除。

底层 `TARGET_ARCH=arm64 ./scripts/build-pkg.sh` 保留正式文件名 `dist/EasyContext-<版本>-macOS-arm64.pkg`（另支持 `x86_64`、默认 `universal`），同样先清空 `dist`；打包过程中若出现外部创建的同名目标，仍会拒绝覆盖。`VERSION` / `BUILD_NUMBER` 环境变量若与工程不同，构建会拒绝。`next-build` 不会让客户端按 build number 提醒更新，也不能用于替换已发布的同版本 Release。新版本安装测试前，请准备高于已安装版本的版本号或构建号，避免 macOS Installer 保留已有新版本。

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

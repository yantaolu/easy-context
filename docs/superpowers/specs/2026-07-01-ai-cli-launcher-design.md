# Easy Context — AI CLI 启动器设计文档

- 日期：2026-07-01
- 状态：已确认决策，待实现
- 目标：右键菜单直接「用某终端运行某命令（如 claude / codex）」于当前目录

## 1. 背景与需求

各类 AI CLI（claude、codex 等）盛行。用户希望右键任意目录 → 菜单直接进终端并运行该 CLI，省去「开终端 → cd → 敲命令」。

## 2. 核心约束与方案（host-relay）

FinderSync 扩展是**沙盒**的，**不能 spawn 进程**，因而无法直接调终端 CLI 注入命令。故采用 **host-relay**：扩展把请求转给**非沙盒宿主**，由宿主执行。

**通信：自定义 URL scheme `easycontext://`**
- 扩展：点菜单 → 构造 `easycontext://run?cmd=<命令id>&dir=<目录>&term=<终端bundleId>` → `NSWorkspace.open(url)`（沙盒允许，且能自动拉起宿主）。
- 宿主：Info.plist 注册 `easycontext` scheme → 收到 URL（SwiftUI `onOpenURL` / AppDelegate）→ 校验 → 在指定终端运行命令。

**安全**：URL 只带**命令 id**（不带原始命令串）+ 目录 + 终端 bundleId。宿主从**用户自己的配置**按 id 查出真正命令再执行。即使他人伪造 URL，也只能触发用户已定义的命令，无法注入任意命令；终端 bundleId 也须在已知/已启用列表内。

## 3. 启动机制：每终端「启动模板」（用户可配置）

不为每个终端硬编码启动方式，而是把「怎么在某终端里于某目录运行某命令」抽象成一条**启动模板**——一条命令字符串，带两个占位符：

- `{dir}` —— 目标目录
- `{cmd}` —— 要运行的命令（来自 commands 配置）

宿主（非沙盒）把占位符**替换后用 `/bin/sh -c` 执行**。内置常见终端的默认模板，**用户可在设置里改写或为任意终端新增**模板。

**内置默认模板**（优先用原生「工作目录 + 执行命令」参数，干净无 `cd` 回显）：

| 终端 | 内置模板 |
|---|---|
| Ghostty | `open -na Ghostty --args --working-directory={dir} -e {cmd}` |
| kitty | `open -na kitty --args --directory {dir} {cmd}` |
| WezTerm | `open -na WezTerm --args start --cwd {dir} -- {cmd}` |
| Alacritty | `open -na Alacritty --args --working-directory {dir} -e {cmd}` |
| Terminal.app | `osascript -e 'tell app "Terminal" to do script "cd {dir} && {cmd}"'`（AppleScript，会回显 cd） |
| iTerm | osascript（iTerm 脚本接口） |

**占位符 = 环境变量（安全关键，免注入）**：
- 执行时宿主把真实目录/命令放进**环境变量** `EC_DIR` / `EC_CMD`，再 `/bin/sh -c "<模板>"`。
- 模板里的 `{dir}` / `{cmd}` 在执行前被替换为 **`"$EC_DIR"` / `"$EC_CMD"`**（只替换占位符 token，不替换值本身）。**值全程走环境变量、绝不拼进命令串** → 天然免注入，路径含空格/引号/中文也不会破坏命令。
- 因此**模板里占位符不要自己加引号**：写 `--working-directory={dir}`（→ `--working-directory="$EC_DIR"`）。
- AppleScript 类（Terminal/iTerm）直接用 `system attribute "EC_DIR"` 从环境读值（AppleScript 里 `quoted form of` 再做 cd 的 shell 引用）——故内置写好、验证过，高级用户可覆盖但默认不用碰。

**取模板逻辑**：`用户覆盖模板[bundleId]` → 否则 `内置默认模板[bundleId]` → 都没有 → 菜单点击提示「请先在设置里填该终端的启动模板」。

- ⚠️ 内置默认逐个真机验证；先跑通 **Terminal + Ghostty**（用户主用），其余尽量支持；调不通的用户可自行改模板。
- 命令结束是否保留窗口：默认**不强加** `exec $SHELL`（更干净），用户可在自己的模板里加。

## 4. 「执行终端」设置（统一，所有命令都用它）

- 配置项 `defaultTerminal`（存 bundleId；空/缺省 = 按解析逻辑取第一个）。
- **与「菜单显示」解耦**：终端列表的开关只决定「用 X 打开终端」是否出现在右键菜单；
  「执行终端」是「命令在哪跑」，只看**装没装**，与开关无关。
- 设置界面下拉框选项 = **全部已安装的终端**（无已安装时常驻「系统 Terminal」兜底，
  保证下拉永不为空、不抖动）。
- 解析逻辑（设置界面与扩展运行时一致，`resolveDefaultTerminal(eligible:preferred:)`，
  其中 eligible = **已安装终端**）：
  1. `defaultTerminal` 指向的终端**已安装** → 用它；
  2. 否则（未配置 / 已卸载）→ **第一个已安装的终端**；
  3. 都没有 → **系统默认终端（Terminal.app）**（常驻兜底）。

### 4.1 PATH（关键）：`-e` 型终端经登录 shell 运行

GUI 启动的进程只有精简 PATH（无 `~/.local/bin`、`~/.npm-global/bin` 等），`-e` 直接
exec 的终端（kitty/WezTerm/Alacritty）会找不到 claude/codex。故这类内置模板
通过用户**登录+交互 shell** 运行命令：`$EC_SHELL -lic {cmd}`（`-l` source `.zprofile`、
`-i` source `.zshrc` → PATH 齐全），与 Terminal.app 的 `do script` 行为一致。
`$EC_SHELL` 由宿主注入（`getpwuid` 取用户登录 shell，兜底 `/bin/zsh`），
与 `EC_DIR`/`EC_CMD` 一样只走环境变量。

### 4.2 Ghostty：改用 AppleScript（1.3.0+）

Ghostty 的 `open ... -e` 外部执行路径**每次弹安全确认**（"Allow Ghostty to execute …"，
GHSA-q9fg-cpmh-c78x，官方不提供关闭）且带 `-n` 会双开窗口——故**放弃 `-e`**。
Ghostty 1.3.0+ 提供 **AppleScript** 接口，用 `input text` 把命令**打进交互 shell**
（而非 `-e` 执行）：单窗口、无「execute」弹框、PATH 天然正确，与 Terminal.app 的
`do script` 等价。内置模板（用 `system attribute` 读 EC_DIR/EC_CMD）：

```
osascript -e 'tell application "Ghostty"' \
  -e 'set cfg to new surface configuration' \
  -e 'set initial working directory of cfg to (system attribute "EC_DIR")' \
  -e 'set win to new window with configuration cfg' \
  -e 'input text (system attribute "EC_CMD") to (terminal 1 of selected tab of win)' \
  -e 'send key "enter" to (terminal 1 of selected tab of win)' \
  -e 'end tell'
```

仅**首次**需一次性自动化授权（macOS TCC「控制 Ghostty」，同 Terminal/iTerm）。

### 4.3 宿主为后台代理（LSUIElement）

宿主用 AppKit AppDelegate 手动管窗（非 SwiftUI 自动开窗）：处理 `easycontext://`
（run/newfile）时**不显示配置窗**（无闪烁）；用户双击 App / 再次打开时才显示配置窗
并临时露出 Dock 图标，关窗退回后台。IPC token 生成 / 模板参考文件写出移到
`applicationDidFinishLaunching`（无论是否显示配置窗都执行）。

## 5. 命令配置

- 新增配置段 `commands`：`[{ name: String, command: String, enabled: Bool }]`。
- 首次生成配置时**预置** `Claude → claude`、`Codex → codex`（启用），用户可增删/改名/改命令/自定义任意命令。
- 设置界面：一块「命令」列表，仿应用列表的 `+ / -` 与开关；每项可编辑 name 与 command。

## 6. 菜单形态

- 解析出「默认终端」后，为每个**启用的命令**生成一项：**「用 \<终端名\> 运行 \<命令名\>」**（如「用 Ghostty 运行 Claude」）。
- 平铺在菜单里（命令通常两三个）；若某天很多可再收进子菜单。
- 无已启用终端时用系统默认终端名。
- 点击 → 构造 `easycontext://run?...` → `NSWorkspace.open`。

## 7. 配置 schema（v3，向后兼容）

在 v2 基础上新增两处，容忍缺字段（旧 v2 配置加载后按默认补齐，宿主 reconcile 时写回 v3）：

```jsonc
{
  "version": 3,
  "items": { ... },
  "terminals": [ ... ],
  "editors": [ ... ],
  "commands": [
    { "name": "Claude", "command": "claude", "enabled": true },
    { "name": "Codex",  "command": "codex",  "enabled": true }
  ],
  "defaultTerminal": "com.mitchellh.ghostty",   // 空/缺省=按解析逻辑取第一个/系统默认
  "terminalTemplates": {                         // 仅存用户覆盖/自定义；缺省用内置
    "com.example.myterm": "open -na MyTerm --args --cwd={dir} -e {cmd}"
  },
  "appearance": { ... }
}
```

- 内置默认模板放在 Core（`TerminalLaunchTemplates.builtin`，宿主取用）；`terminalTemplates` 只存用户改写/新增的。
- 设置界面「默认终端」下方，为每个已启用终端显示一个**启动模板输入框**（预填「用户覆盖或内置默认」的当前值；用户编辑即写为覆盖）。

## 8. 分阶段实现计划（任务级）

**阶段 1 — Core（可 swift test）**
- `CommandEntry` 模型；`Settings` 加 `commands`、`defaultTerminal`、`terminalTemplates`，容错解码，v3。
- 默认命令预置（Claude/Codex）。
- `TerminalLaunchTemplates.builtin`（bundleId→模板）+ 取模板函数 `template(for:overrides:) -> String?`（用户覆盖优先、否则内置）。
- 占位符替换 + shell 转义纯函数：`renderTemplate(_:dir:cmd:) -> String`（对 {dir}/{cmd} 做 shell 转义），含单元测试（含空格/引号/中文路径不破坏、不注入）。
- 「默认终端解析」纯函数：`resolveDefaultTerminal(terminals:, defaultTerminal:) -> KnownApp?/系统默认`，含单元测试（配置/卸载回退/无启用回退系统默认）。

**阶段 2 — URL scheme 打通（可验证往返）**
- 宿主 Info.plist（project.yml）注册 `easycontext` scheme。
- 宿主接收 URL（`onOpenURL`），解析 cmd/dir/term，先只弹提示/记日志验证。
- 扩展侧临时加个测试菜单项，`NSWorkspace.open` 一个 URL，确认宿主被拉起并收到参数。

**阶段 3 — TerminalLauncher（宿主，真机验证）**
- 宿主 URL 处理：按 cmd id 从配置查命令 → 校验终端在白名单 → 取模板（Core）→ `renderTemplate` 替换转义 → `/bin/sh -c` 执行。
- 真机验证内置模板：先 **Terminal + Ghostty** 跑通「在目录里干净地起 claude」，再验 iTerm/kitty/WezTerm/Alacritty；调不通的靠用户模板兜底。

**阶段 4 — 扩展菜单集成**
- 扩展读配置里的 commands + 解析默认终端 → 生成「用 XX 运行 YY」菜单项（tag 索引，遵循既有线程/缓存约定）。
- 点击构造 URL 并 open。

**阶段 5 — 设置界面**
- 「默认终端」下拉（已启用终端 + 系统默认，按解析逻辑给默认选中）。
- 「命令」列表管理（增删、改名、改命令、开关），写回配置。
- 每个已启用终端一个**启动模板输入框**（预填「用户覆盖或内置默认」，编辑即写为覆盖；可「恢复默认」）。

**阶段 6 — 收尾**
- URL 参数安全校验（命令按 id 查、终端白名单、目录存在性）。
- 文档：本设计文档定稿；README 记录 `easycontext://` scheme 约定与「命令」功能；设计文档 §7 若涉及新约束补充。

## 9. 已知风险

- 个别终端的启动参数可能调不通（非 Terminal/Ghostty），届时对该终端标注「运行命令暂不支持」，不影响其「用编辑器/终端打开目录」等既有功能。
- URL scheme 可被其它 App 触发——已用「命令按 id 查配置、终端白名单」把风险限制在用户已定义的命令内。

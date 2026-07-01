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

## 3. 「在终端运行命令」配方（宿主，非沙盒）

宿主可自由 spawn。按终端分策略，**优先用原生「工作目录 + 执行命令」参数**（干净、无 `cd` 回显）：

| 终端 | 方式 |
|---|---|
| Ghostty | `open -na Ghostty --args --working-directory=<dir> -e <cmd>`（真机核对参数名） |
| kitty | `open -na kitty --args --directory <dir> <cmd>` |
| WezTerm | `open -na WezTerm --args start --cwd <dir> -- <cmd>` |
| Alacritty | `open -na Alacritty --args --working-directory <dir> -e <cmd>` |
| Terminal.app | AppleScript `do script "cd <dir> && <cmd>"`（会回显 cd，机制所限） |
| iTerm | AppleScript（iTerm 脚本接口） |
| 兜底 | 写临时 `.command`（`cd <dir>; <cmd>`）用 Terminal.app 打开 |

- ⚠️ 每个终端的启动参数**逐个真机验证**；先跑通 **Terminal + Ghostty**（用户主用），其余尽量支持、验证到哪算哪，调不通的在设置里对该终端标注「运行命令暂不支持」。
- 命令结束是否保留窗口：默认**不强加** `exec $SHELL`（更干净），后续可作为选项。

## 4. 「默认终端」设置（统一，所有命令都用它）

- 配置项 `defaultTerminal`（存 bundleId，或 sentinel `"system"` 表示系统默认 Terminal.app）。
- 设置界面下拉框选项 = **已启用且已安装的终端** + 常驻项「系统默认终端」。
- 解析逻辑（设置界面与扩展运行时一致）：
  1. `defaultTerminal` 指向的终端**已启用且已安装** → 用它；
  2. 否则（未配置 / 已卸载）→ **第一个已启用且已安装的终端**；
  3. 都没有 → **系统默认终端（Terminal.app）**（常驻兜底）。

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
  "appearance": { ... }
}
```

## 8. 分阶段实现计划（任务级）

**阶段 1 — Core（可 swift test）**
- `CommandEntry` 模型；`Settings` 加 `commands`、`defaultTerminal`，容错解码，v3。
- 默认命令预置（Claude/Codex）。
- 「默认终端解析」纯函数：`resolveDefaultTerminal(terminals:, defaultTerminal:) -> KnownApp?/系统默认`，含单元测试（配置/卸载回退/无启用回退系统默认）。

**阶段 2 — URL scheme 打通（可验证往返）**
- 宿主 Info.plist（project.yml）注册 `easycontext` scheme。
- 宿主接收 URL（`onOpenURL`），解析 cmd/dir/term，先只弹提示/记日志验证。
- 扩展侧临时加个测试菜单项，`NSWorkspace.open` 一个 URL，确认宿主被拉起并收到参数。

**阶段 3 — TerminalLauncher（宿主，真机验证）**
- 宿主里按终端 bundleId 的启动配方（先 Terminal + Ghostty，再 iTerm/kitty/WezTerm/Alacritty，兜底 `.command`）。
- 宿主 URL 处理：按 cmd id 从配置查命令 → 校验终端 → 用配方在目录运行。
- 逐终端真机验证「在目录里干净地跑起 claude」。

**阶段 4 — 扩展菜单集成**
- 扩展读配置里的 commands + 解析默认终端 → 生成「用 XX 运行 YY」菜单项（tag 索引，遵循既有线程/缓存约定）。
- 点击构造 URL 并 open。

**阶段 5 — 设置界面**
- 「默认终端」下拉（已启用终端 + 系统默认，按解析逻辑给默认选中）。
- 「命令」列表管理（增删、改名、改命令、开关），写回配置。

**阶段 6 — 收尾**
- URL 参数安全校验（命令按 id 查、终端白名单、目录存在性）。
- 文档：本设计文档定稿；README 记录 `easycontext://` scheme 约定与「命令」功能；设计文档 §7 若涉及新约束补充。

## 9. 已知风险

- 个别终端的启动参数可能调不通（非 Terminal/Ghostty），届时对该终端标注「运行命令暂不支持」，不影响其「用编辑器/终端打开目录」等既有功能。
- URL scheme 可被其它 App 触发——已用「命令按 id 查配置、终端白名单」把风险限制在用户已定义的命令内。

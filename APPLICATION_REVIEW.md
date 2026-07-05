# Easy Context 应用审查与核心设计沉淀

审查日期：2026-07-05

## 审查范围

本次按“功能 -> 设计 -> 编码”的路径复查全量代码：

- 宿主 App：`EasyContext/`
- FinderSync 扩展：`EasyContextFinder/`
- 核心逻辑 Swift Package：`EasyContextCore/`
- 构建、打包与说明：`project.yml`、`scripts/`、`packaging/`、`README.md`

前提采用用户说明：正常交互下同时只会出现一个 Finder 右键菜单。因此，本次不把“多个右键菜单同时存在时共享菜单状态被覆盖”列为问题。

## 功能设计

Easy Context 是 macOS Finder 右键菜单增强工具，目标是在 Finder 文件、目录和空白区域上提供高频上下文操作：

- 复制完整路径。
- 复制相对路径：优先相对最近的 Git 仓库根；不在仓库内时回退到 `~/...`；再否则返回绝对路径。
- 用已安装终端打开目标目录。
- 用已安装编辑器打开目标目录。
- 在执行终端中运行用户配置命令，如 `claude`、`codex`。
- 新建模板文件：Markdown、Text、Shell、JSON。
- 设置界面管理菜单项、终端、编辑器、自定义命令、默认执行终端、终端启动模板、图标样式。

多选目标规则：

- 复制完整路径 / 复制相对路径：复制所有原始选中项。
- 打开终端 / 打开编辑器：目录取自身，文件取父目录，按路径去重后打开这些目录。
- 运行命令 / 新建文件：一次性动作，使用去重后的第一个目录。

## 架构设计

| 层 | 路径 | 职责 | 设计评价 |
|---|---|---|---|
| 核心库 | `EasyContextCore/` | 配置模型、路径解析、App 清单、命令模板、新文件创建、单元测试 | 边界清晰，便于纯逻辑测试 |
| Finder 扩展 | `EasyContextFinder/` | 构建右键菜单、读取配置、解析目标、通过 LaunchServices 或 URL 协议发起动作 | 符合 FinderSync 沙盒约束 |
| 宿主 App | `EasyContext/` | 设置 UI、共享配置写入、处理 `easycontext://` URL、执行命令 / 新建文件 | 后台代理型设计合理，避免右键动作弹设置窗 |

宿主和扩展通过 `~/.easy-context/config.json` 共享配置。`ConfigStore` 使用 `getpwuid(getuid())` 获取真实用户 home，避免沙盒扩展中的 `NSHomeDirectory()` 指向容器路径，导致宿主和扩展读写不同配置。

## 核心数据流

### 菜单显示

1. Finder 调用 `FinderSyncExtension.menu(for:)`。
2. 扩展解析当前目标 URL，并保存成本次菜单快照。
3. 扩展读取 `config.json`，按配置、安装态和启用状态构建菜单。
4. App 图标、安装态、配置按缓存策略复用，降低每次右键的开销。

### 打开终端/编辑器

1. 菜单项点击后用 `tag` 定位构建菜单时的 App 列表。
2. 目标统一转为目录集合：目录取自身，文件取父目录，多选按路径去重。
3. 扩展用 `NSWorkspace.open(..., withApplicationAt:)` 打开，避免沙盒内 spawn `/usr/bin/open`。

### 运行命令

1. 扩展从去重后的目标目录集合中选择第一个目录，构造 `easycontext://run` URL。
2. URL 中携带命令 id、命令显示名、目录、终端 bundle id 和 IPC token。
3. 宿主校验 token、目录存在、命令仍在配置中且可运行。
4. 宿主读取终端启动模板，将 `{dir}`、`{cmd}` 渲染为环境变量引用，通过 `/bin/sh -c` 启动。
5. 真实目录和命令只通过环境变量传递，降低 shell 注入风险。

### 新建文件

1. 扩展从去重后的目标目录集合中选择第一个目录，构造 `easycontext://newfile` URL。
2. 宿主校验 token、目录存在、模板合法。
3. 宿主弹命名面板，用户输入文件名。
4. `NewFileMaker` 清理路径成分、解析扩展名、用原子创建方式按重名规则生成文件。
5. 创建成功后 Finder 选中新文件。

## 稳定性与安全约束

- URL 动作使用 `.ipc-token` 验证，避免网页或外部 App 直接伪造 `easycontext://` 执行命令 / 新建文件。
- 命令执行优先按配置中的命令 id 查找，不信任 URL 中的任意命令字符串。
- 终端模板通过环境变量传值，不把目录和命令直接拼入 shell 字符串。
- 配置解码对缺字段、坏数组项做容错；配置整体损坏时备份为 `config.json.bak`，不直接覆盖用户原文件。
- FinderSync 菜单目标在构建时快照化，避免点击时 Finder 选区变化导致动作目标漂移。
- FinderSync 缓存使用 `NSLock` 保护，耗时 I/O、LaunchServices 查询和图标渲染放在锁外。
- 相对路径解析用字符串向上遍历，避免 Finder 桥接 URL 在根路径上产生无限 `../` 的历史问题。
- 覆盖安装脚本会显式注册新版 FinderSync 扩展、启动宿主并重启 Finder，降低安装后右键菜单临时消失的风险。

## 仍存在的问题

| 编号 | 严重级别 | 位置 | 问题 | 影响 | 建议 |
|---|---|---|---|---|---|
| R1 | 低 | `EasyContext/CommandLauncher.swift:39-41` | 命令 id 查不到时按 `cmd` 显示名回退，且显示名允许重复。 | 正常新版本 URL 有 id，不受影响；但升级兼容或手改配置导致 id 不匹配时，重复名称会执行第一个同名命令。 | 若后续要收紧兼容逻辑，建议仅当同名命令唯一时才允许 name 回退，否则提示重新打开菜单。 |
| R2 | 低 | `EasyContext/ContentView.swift:147-163` | 命令列表的焦点变化都会触发 `flushCommands()`，包括从名称框切到命令框。 | 频繁持久化和 normalize 通常可接受；但输入体验上，空名称在切焦点时会立刻变成默认名。 | 若后续追求更细腻 UX，可只在焦点离开整行 / 列表 / 窗口时 flush。 |
| R3 | 低 | `EasyContextCore/Sources/EasyContextCore/NewFileMaker.swift:62-67` | `write(2)` 循环未显式处理返回 0 的异常情况。 | 普通文件写入几乎不会返回 0；若底层异常返回 0，循环无法前进，理论上可能卡住。 | 在 `result == 0` 时抛出 `POSIXError(.EIO)` 或自定义错误。 |
| R4 | 低 | AppKit / FinderSync 集成层 | 自动测试集中在 `EasyContextCore`，宿主 URL 处理、FinderSync 菜单构建、设置 UI 仍缺少自动化覆盖。 | 纯逻辑质量可验证，但集成行为仍依赖人工回归，升级 macOS / Xcode 时风险偏高。 | 增加可注入依赖的菜单构建单元测试；对 URL handler 增加集成测试；关键 UI 用 XCUITest 或脚本化 smoke test。 |

## 验证结果

已执行：

```bash
cd EasyContextCore
swift test
```

结果：59 个 XCTest 全部通过。

未重复执行完整 `xcodebuild`：该命令会注册同 bundle id 的调试 App，并可能打断当前 FinderSync 实例，影响本机右键菜单。安装脚本已经覆盖正式安装后的扩展注册和 Finder 重启流程。

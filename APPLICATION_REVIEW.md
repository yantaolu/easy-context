# Easy Context 应用审查与核心设计沉淀

审查日期：2026-07-05

更新日期：2026-07-05

本轮处理结论：

- R1：已处理。`FileManager.createFile` 可以避免常规覆盖，但不是最严格解法；当前实现改为 `open(..., O_CREAT | O_EXCL)` 原子创建，竞争撞名时重新取下一个序号。
- R2：已处理。扩展侧配置缓存复用 `ConfigStore.fileToken()`，用 `mtime + size` 判断配置变动。
- R3：已定策略并更新实现/文档。复制类复制所有原始目标；打开类统一使用目标目录集合（目录取自身、文件取父目录、按路径去重）；运行命令/新建文件是一次性动作，使用去重后的第一个目录。不采用多选时隐藏菜单项，避免菜单跳变。
- R4：按决策不处理。
- R5：已处理。README 已从 `NSRecursiveLock` 修正为 `NSLock`，并强调非递归锁约束。
- R6：按决策不处理。
- R7：已增强测试。新增并发同名新建文件测试、`FileToken` size 识别测试。

## 审查范围

本次按“功能 -> 设计 -> 编码”的路径审查全量代码：

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

## 架构设计

整体拆成三层：

| 层 | 路径 | 职责 | 设计评价 |
|---|---|---|---|
| 核心库 | `EasyContextCore/` | 配置模型、路径解析、App 清单、命令模板、新文件创建、单元测试 | 边界清晰，便于纯逻辑测试 |
| Finder 扩展 | `EasyContextFinder/` | 构建右键菜单、读取配置、解析目标、通过 LaunchServices 或 URL 协议发起动作 | 基本符合 FinderSync 沙盒约束 |
| 宿主 App | `EasyContext/` | 设置 UI、共享配置写入、处理 `easycontext://` URL、执行命令/新建文件 | 后台代理型设计合理，避免右键动作弹设置窗 |

宿主和扩展通过 `~/.easy-context/config.json` 共享配置。`ConfigStore` 使用 `getpwuid(getuid())` 获取真实用户 home，避免沙盒扩展中的 `NSHomeDirectory()` 指向容器路径，导致宿主和扩展读写不同配置。

## 核心数据流

### 菜单显示

1. Finder 调用 `FinderSyncExtension.menu(for:)`。
2. 扩展解析当前目标 URL，并保存成本次菜单快照。
3. 扩展读取 `config.json`，按配置、安装态和启用状态构建菜单。
4. App 图标、安装态、配置按缓存策略复用，降低每次右键的开销。

### 打开终端/编辑器

1. 菜单项点击后用 `tag` 定位构建菜单时的 App 列表。
2. 打开终端/编辑器统一转为目录集合：目录取自身，文件取父目录，多选按路径去重。
3. 扩展用 `NSWorkspace.open(..., withApplicationAt:)` 打开，避免沙盒内 spawn `/usr/bin/open`。

### 运行命令

1. 扩展从去重后的目标目录集合中选择第一个目录，构造 `easycontext://run` URL。
2. URL 中携带命令 id、目录、终端 bundle id 和 IPC token。
3. 宿主校验 token、目录存在、命令仍在配置中且可运行。
4. 宿主读取终端启动模板，将 `{dir}`、`{cmd}` 渲染为环境变量引用，通过 `/bin/sh -c` 启动。
5. 真实目录和命令只通过环境变量传递，降低 shell 注入风险。

### 新建文件

1. 扩展从去重后的目标目录集合中选择第一个目录，构造 `easycontext://newfile` URL。
2. 宿主校验 token、目录存在、模板合法。
3. 宿主弹命名面板，用户输入文件名。
4. `NewFileMaker` 清理路径成分、解析扩展名、按重名规则生成文件名并写入模板内容。
5. 创建成功后 Finder 选中新文件。

## 稳定性与安全约束

- URL 动作使用 `.ipc-token` 验证，避免网页或外部 App 直接伪造 `easycontext://` 执行命令/新建文件。
- 命令执行按配置中的命令 id 查找，不信任 URL 中的任意命令字符串。
- 终端模板通过环境变量传值，不把目录和命令直接拼入 shell 字符串。
- 配置解码对缺字段、坏数组项做容错；配置整体损坏时备份为 `config.json.bak`，不直接覆盖用户原文件。
- FinderSync 菜单目标在构建时快照化，避免点击时 Finder 选区变化导致动作目标漂移。
- FinderSync 缓存使用锁保护，耗时 I/O、LaunchServices 查询和图标渲染尽量放在锁外。
- 相对路径解析用字符串向上遍历，避免 Finder 桥接 URL 在根路径上产生无限 `../` 的历史问题。

## 审查发现

| 编号 | 严重级别 | 位置 | 问题 | 影响 | 建议 |
|---|---|---|---|---|---|
| R1 | 中 | `EasyContextCore/Sources/EasyContextCore/NewFileMaker.swift` | “重名自动加序号、永不覆盖”原先是先 `fileExists` 后 `write`，检查和写入之间不是原子操作。 | 若外部进程或另一次创建在极短时间内抢先创建同名文件，可能违背“永不覆盖”的语义。 | 已处理：改为 `open(..., O_CREAT | O_EXCL)` 原子创建；竞争撞名时重算下一个文件名。已增加并发同名创建测试。 |
| R2 | 中 | `EasyContextFinder/FinderSyncExtension.swift` | 扩展侧配置缓存原先只看 `mtime`，而宿主侧已有 `mtime + size` 的 `FileToken`。 | 如果配置在极短时间内被连续写入，且文件系统暴露的修改时间未变化，扩展可能继续使用旧配置。 | 已处理：扩展侧复用 `ConfigStore.fileToken()`。已增加 size 参与指纹判断的测试。 |
| R3 | 低 | `EasyContextFinder/FinderSyncExtension.swift` / `README.md` | 多选目标语义需要明确。 | 如果不写清楚，跨目录多选时用户可能误解哪些动作作用于全部目标、哪些只作用一次。 | 已处理：复制类复制所有原始目标；打开类使用全部去重目录；运行命令/新建文件使用第一个去重目录。当前不采用多选时隐藏菜单项。 |
| R4 | 低 | `EasyContext/CommandLauncher.swift:39-41` | 命令 id 查不到时按 name 回退，且允许重复 name。 | 正常新版本 URL 有 id，不受影响；但升级兼容或手改配置导致 id 不匹配时，重复名称会执行第一个同名命令。 | 按决策不处理。 |
| R5 | 低 | `README.md` | README 写“本项目用 `NSRecursiveLock`”，实际代码使用 `NSLock`。 | 贡献者可能误以为允许递归加锁，后续修改中更容易引入死锁或错误嵌套。 | 已处理：README 修正为 `NSLock`，并说明非递归锁约束。 |
| R6 | 低 | `EasyContext/ContentView.swift:147-163` | 命令列表的焦点变化都会触发 `flushCommands()`，包括从名称框切到命令框。 | 频繁持久化和 normalize，通常可接受；但输入体验上，空名称在切焦点时会立刻变成默认名。 | 按决策不处理。 |
| R7 | 低 | 测试覆盖 | 自动测试集中在 `EasyContextCore`，宿主 URL 处理、FinderSync 菜单构建、设置 UI 没有自动化测试。 | 纯逻辑质量可验证，但集成行为仍依赖人工回归，升级 macOS/Xcode 时风险偏高。 | 已增强核心测试：并发新建文件和配置指纹测试。FinderSync/AppKit 集成测试仍是后续可选增强。 |

## 正向设计结论

- 框架拆分合理：核心逻辑和 AppKit/FinderSync 边界分离，测试集中在核心库，方向正确。
- 配置容错设计较稳：缺字段、坏数组项、损坏文件、外部改动、自写回环都已有处理。
- FinderSync 线程模型处理较谨慎：缓存加锁、目标快照、图标离屏绘制、深浅色读取均考虑了工作线程约束。
- 命令执行安全边界清楚：URL token、命令 id、目录存在校验、环境变量传值共同降低误执行和注入风险。
- 用户体验上，设置窗固定、列表即时刷新、配置损坏/写盘失败/扩展未启用都有提示，比静默失败更可诊断。

## 验证结果

已执行：

```bash
cd EasyContextCore
swift test
```

结果：59 个 XCTest 全部通过。

首次在沙盒内运行时被 SwiftPM/Clang 用户级缓存写入权限拦截；按权限要求在非沙盒环境重跑后通过。

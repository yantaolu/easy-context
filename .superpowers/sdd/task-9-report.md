# Task 9 Report: XcodeGen 生成宿主 App + FinderSync 扩展

**状态：** DONE  
**Commit hash：** 814bbc8  
**分支：** phase-b  
**日期：** 2026-06-30

---

## 做了什么

### Step 1：安装 XcodeGen
`xcodegen` 未预装，通过 `brew install xcodegen` 安装了 2.45.4 版本。

### Step 2–4：写源码文件
按 brief 逐字创建以下文件：
- `project.yml`（仓库根）
- `EasyContext/EasyContextApp.swift`
- `EasyContext/ContentView.swift`
- `EasyContext/Info.plist`（空 dict，由 xcodegen 注入内容）
- `EasyContextFinder/FinderSyncExtension.swift`
- `EasyContextFinder/Info.plist`（空 dict，由 xcodegen 注入 NSExtension）

### Step 5：生成工程并编译
`xcodegen generate` 成功生成 `EasyContext.xcodeproj`，同时将 Info.plist 填充了完整内容（CFBundleIdentifier、NSExtension 等字段均正确注入）。

`xcodebuild` 命令（按 brief 逐字使用）：
```
xcodebuild -project EasyContext.xcodeproj -scheme EasyContext -configuration Debug \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

结果：`** BUILD SUCCEEDED **`

.appex 确认生成：
```
build/Build/Products/Debug/EasyContext.app/Contents/PlugIns/EasyContextFinder.appex/Contents/
```

### .gitignore 更新
在现有 `.gitignore` 末尾追加：
```
EasyContext.xcodeproj/
build/
```

### Step 7：提交
```
git add project.yml EasyContext EasyContextFinder .gitignore
git commit -m "feat(app): XcodeGen 生成宿主 App 与 FinderSync 扩展（ad-hoc 签名，无 App Group）"
```

---

## 文件清单

| 文件 | 状态 |
|------|------|
| `project.yml` | 新建，入库 |
| `EasyContext/EasyContextApp.swift` | 新建，入库 |
| `EasyContext/ContentView.swift` | 新建，入库 |
| `EasyContext/Info.plist` | 新建（xcodegen 注入后修改），入库 |
| `EasyContextFinder/FinderSyncExtension.swift` | 新建，入库 |
| `EasyContextFinder/Info.plist` | 新建（xcodegen 注入后修改），入库 |
| `.gitignore` | 修改（追加两行），入库 |
| `EasyContext.xcodeproj/` | 生成，.gitignore 排除，未入库 |
| `build/` | 生成，.gitignore 排除，未入库 |

---

## xcodegen 输出关键段

```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at /Volumes/Samsung/codes/easy-context/EasyContext.xcodeproj
```

xcodegen 自动将 project.yml 中 `info.properties` 合并到各目标的 Info.plist，包括：
- 宿主 App：CFBundleDisplayName、LSMinimumSystemVersion、LSUIElement 等标准字段
- 扩展：NSExtension 字典（含 NSExtensionPointIdentifier 和 NSExtensionPrincipalClass）

---

## xcodebuild 输出关键段

```
Resolved source packages:
  EasyContextCore: /Volumes/Samsung/codes/easy-context/EasyContextCore

note: Target dependency graph (4 targets)
    Target 'EasyContext' in project 'EasyContext'
        ➜ Explicit dependency on target 'EasyContextFinder' in project 'EasyContext'
        ➜ Explicit dependency on target 'EasyContextCore' in project 'EasyContextCore'
    Target 'EasyContextFinder' in project 'EasyContext'
        ➜ Explicit dependency on target 'EasyContextCore' in project 'EasyContextCore'

...（编译 EasyContextCore、EasyContextFinder、EasyContext 各模块）...

Copy .../Debug/EasyContextFinder.appex .../Debug/EasyContext.app/Contents/PlugIns
ValidateEmbeddedBinary .../EasyContext.app/Contents/PlugIns/EasyContextFinder.appex

** BUILD SUCCEEDED **
```

---

## .appex 确认

```
/Volumes/Samsung/codes/easy-context/build/Build/Products/Debug/
  EasyContext.app/
    Contents/
      PlugIns/
        EasyContextFinder.appex/   ← 确认存在
          Contents/
```

---

## 对 brief 的偏离

无实质偏离。以下为细节说明：

1. **Info.plist 由 xcodegen 填充**：brief 要求 plist 初始为空 `<dict></dict>`，`xcodegen generate` 执行后自动注入了完整内容（CFBundleIdentifier、NSExtension 等）。这是预期行为，brief 也有注释说明。入库的是 xcodegen 填充后的版本。
2. **Step 6 未执行**：按任务要求跳过，由用户手动操作。

---

## Commit Hash

`814bbc8`  
分支：`phase-b`

---

## 疑虑

无编译错误。以下为可能的运行期注意点（不影响编译验证）：

- ad-hoc 签名的 FinderSync 扩展能否被 macOS 系统设置识别并加载，取决于系统 SIP 设置和 Gatekeeper 策略。brief 中已预留回退方案（`codesign --force --deep -s -` 或使用免费 Apple ID 签名）。
- `CODE_SIGNING_ALLOWED=NO` 导致 .appex 未签名，系统可能拒绝加载。若 Step 6 遇到问题，建议改用 `CODE_SIGN_IDENTITY="-"` 加 ad-hoc 签名（即只去掉 `CODE_SIGNING_ALLOWED=NO`）。

---

## 修复：签名 + plist 单来源

### 改了什么

**问题 1（签名）：**
- `project.yml` 全局 `settings.base` 新增 `CODE_SIGNING_REQUIRED: "YES"` 和 `CODE_SIGNING_ALLOWED: "YES"`，与已有的 `CODE_SIGN_IDENTITY: "-"` 共同确保默认即 ad-hoc 签名。
- 计划文件 `docs/superpowers/plans/2026-06-30-easy-context.md` 中所有 5 处旧命令（`CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`）统一替换为标准命令（`CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES`）。

**问题 2（plist 单来源）：**
- `git rm --cached EasyContext/Info.plist EasyContextFinder/Info.plist`：将两个由 xcodegen 生成的 Info.plist 从 git 追踪移除。
- `.gitignore` 追加 `EasyContext/Info.plist` 和 `EasyContextFinder/Info.plist`，避免重新生成后意外入库。
- `project.yml` 的 `info.properties` 已包含 NSExtension 字典（NSExtensionPointIdentifier=com.apple.FinderSync、NSExtensionPrincipalClass=$(PRODUCT_MODULE_NAME).FinderSyncExtension），是唯一权威来源；xcodegen 自动补全 CFBundle 标准键。

### 重建 xcodebuild 关键输出

```
xcodegen generate  →  Created project at EasyContext.xcodeproj

xcodebuild ... CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES build

Signing Identity:     "Sign to Run Locally"
/usr/bin/codesign --force --sign - --timestamp=none --generate-entitlement-der ...EasyContextFinder.appex
...
** BUILD SUCCEEDED **
```

### codesign -dv 的 Signature 行

```
# .appex
codesign -dv build/Build/Products/Debug/EasyContext.app/Contents/PlugIns/EasyContextFinder.appex 2>&1 | grep -i Signature
Signature=adhoc

# .app
codesign -dv build/Build/Products/Debug/EasyContext.app 2>&1 | grep -i Signature
Signature=adhoc
```

### git status / git ls-files | grep -i info.plist

```
git status:
  deleted:    EasyContext/Info.plist       (staged for removal)
  deleted:    EasyContextFinder/Info.plist (staged for removal)
  modified:   .gitignore
  modified:   docs/superpowers/plans/2026-06-30-easy-context.md
  modified:   project.yml

git ls-files | grep -i info.plist:
(no output — 两个 Info.plist 已不入库)
```

生成的 `EasyContextFinder/Info.plist` 本地存在，含正确 NSExtension（NSExtensionPointIdentifier=com.apple.FinderSync），但不入库（被 .gitignore 忽略）。

### Commit hash

见下方提交后更新。

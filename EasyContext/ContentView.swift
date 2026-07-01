import SwiftUI
import UniformTypeIdentifiers
import EasyContextCore

// SwiftUI 也有个 Settings（场景）类型，显式指向我们的配置类型以消歧。
private typealias CoreSettings = EasyContextCore.Settings

// 全局单一选中：同一时刻只有一个列表行高亮，切列表/点空白即自动取消上一个。
private enum RowSelection: Hashable {
    case terminal(String)
    case editor(String)
    case command(String) // 命令 id（稳定 UUID）
}

struct ContentView: View {
    @StateObject private var store = SettingsStore()
    @State private var selection: RowSelection?
    @FocusState private var focusedCommand: String? // 命令输入框焦点键（"name-<id>"/"cmd-<id>"）
    // 统一行高（内容 18 + 上下 insets 各 5 = 28），左右两列开关据此对齐。
    private let listRowContentHeight: CGFloat = 18
    // 终端/菜单项固定显示 3 行的容器高度（贴合 3 行）。
    private let threeRowsHeight: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            if store.configCorrupt { corruptBanner }
            if !store.extensionEnabled { extensionBanner }
            HStack(spacing: 0) {
                leftColumn
                columnDivider
                rightColumn
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 800, height: 494) // 高 = 800 × 0.618
    }

    // MARK: - 左列：菜单项 / 菜单图标 / 编辑器

    private var leftColumn: some View {
        VStack(spacing: 0) {
            sectionBox(menuItemsSection)
            rowDivider
            sectionBox(iconSection)
            rowDivider
            sectionBox(appColumn("菜单显示的编辑器", category: .editor), fill: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 右列：其他 / 终端 / 自定义命令

    private var rightColumn: some View {
        VStack(spacing: 0) {
            sectionBox(appColumn("菜单显示的终端", category: .terminal, fixedThreeRows: true))
            rowDivider
            sectionBox(commandColumn, fill: true)
            rowDivider
            sectionBox(otherSection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var menuItemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("菜单项")
            // 也用原生 List（不可选中），与右列「终端」List 同机制→开关精确对齐。
            List {
                menuRow("复制路径", \.copyFullPath)
                menuRow("复制相对路径", \.copyRelativePath)
                menuRow("新建文件", \.newFile)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, listRowContentHeight)
            .scrollDisabled(true)
            .frame(height: threeRowsHeight)
        }
    }

    private func menuRow(_ title: String,
                         _ keyPath: WritableKeyPath<CoreSettings.Items, Bool>) -> some View {
        itemToggle(title, keyPath)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
    }

    private var iconSection: some View {
        HStack(spacing: 8) {
            sectionTitle("应用图标")
            Spacer()
            Picker("", selection: Binding(
                get: { store.settings.appearance.appIconStyle },
                set: { store.settings.appearance.appIconStyle = $0; store.persist() })) {
                Text("黑白").tag(CoreSettings.AppIconStyle.monochrome)
                Text("彩色").tag(CoreSettings.AppIconStyle.color)
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    // 单行：标题左，两个 link 按钮右对齐。
    private var otherSection: some View {
        HStack(spacing: 8) {
            sectionTitle("其他")
            Spacer()
            Button("打开配置目录") { openConfigDirectory() }
                .buttonStyle(.link)
            Button("访达扩展设置") { openExtensionSettings() }
                .buttonStyle(.link)
                .padding(.leading, 12)
        }
    }

    // 每个组别的统一内边距；fill=true 的组撑满剩余高度（内部列表可滚动）。
    private func sectionBox<Content: View>(_ content: Content, fill: Bool = false) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
    }

    // 组间横分隔线（与组内容边缘对齐）。
    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    // MARK: - 自定义命令组（默认终端下拉 + 命令列表）

    private var commandColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("自定义命令")
            defaultTerminalPicker
            if TerminalLaunch.externalExecUnreliable.contains(store.resolvedDefaultTerminal) {
                Text("⚠ 该终端从外部运行命令会弹确认且可能多开窗口，建议改用 Terminal / iTerm")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            List(selection: commandSelBinding) {
                ForEach(store.settings.commands) { cmd in
                    commandRow(cmd)
                        .tag(cmd.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // 焦点离开命令输入框（点别处/切行）→ 落盘，兜住防抖未触发的收尾。
            .onChange(of: focusedCommand) { _ in store.flushCommands() }
            commandFooterBar
        }
        .frame(maxWidth: .infinity)
    }

    private var defaultTerminalPicker: some View {
        HStack(spacing: 8) {
            Text("执行终端").font(.callout).foregroundStyle(.secondary)
            Spacer()
            // 始终是下拉框（选项永不为空，无已安装时只列系统 Terminal）→ 不抖动。
            // 选项 = 全部已安装终端，与「菜单显示」开关无关。
            Picker("", selection: Binding(
                get: { store.resolvedDefaultTerminal },
                set: { store.setDefaultTerminal($0) })) {
                ForEach(store.terminalOptions) { t in
                    Text(t.name).tag(t.bundleId)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.bottom, 2)
    }

    private func commandRow(_ cmd: CommandEntry) -> some View {
        let id = cmd.id
        return HStack(spacing: 8) {
            TextField("名称", text: Binding(
                get: { store.command(id)?.name ?? "" },
                set: { store.updateCommandName(id: id, $0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 96)
                .focused($focusedCommand, equals: "name-\(id)")
                .onSubmit { store.flushCommands() }
            TextField("命令，如 claude", text: Binding(
                get: { store.command(id)?.command ?? "" },
                set: { store.updateCommandString(id: id, $0) }))
                .textFieldStyle(.roundedBorder)
                .focused($focusedCommand, equals: "cmd-\(id)")
                .onSubmit { store.flushCommands() }
        }
    }

    private var commandFooterBar: some View {
        HStack(spacing: 4) {
            Button { store.addCommand() } label: {
                Image(systemName: "plus").frame(width: 22, height: 18)
            }
            .help("新增命令")
            Button { removeSelectedCommand() } label: {
                Image(systemName: "minus").frame(width: 22, height: 18)
            }
            .disabled(selectedCommandId == nil)
            .help("删除选中的命令")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private var selectedCommandId: String? {
        if case .command(let id) = selection { return id }
        return nil
    }

    private func removeSelectedCommand() {
        guard let id = selectedCommandId else { return }
        store.removeCommand(id: id)
        selection = nil
    }

    // 原生 List：自带选中高亮 + 点空白取消 + 统一 padding。
    // fixedThreeRows=true → 固定 3 行高（≤3 不滚动、>3 滚动）；否则撑满剩余。
    private func appColumn(_ title: String, category: AppCategory,
                           fixedThreeRows: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            List(selection: appSelBinding(category)) {
                ForEach(store.entries(category)) { entry in
                    appRow(entry, category: category)
                        .tag(entry.bundleId)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, listRowContentHeight)
            // 保留 List 正常交互 + 内容不足时也有橡皮筋回弹（不禁用滚动）。
            .alwaysBounce()
            .frame(height: fixedThreeRows ? threeRowsHeight : nil)
            .frame(maxHeight: fixedThreeRows ? nil : .infinity)
            listFooterBar(category: category)
        }
        .frame(maxWidth: .infinity)
    }

    private func appRow(_ entry: AppEntry, category: AppCategory) -> some View {
        let installed = store.isInstalled(entry)
        return HStack(spacing: 10) {
            if let icon = store.icon(entry) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: category == .terminal ? "terminal"
                      : "chevron.left.forwardslash.chevron.right")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
            }
            Text(entry.name).foregroundStyle(installed ? .primary : .secondary)
            if !installed {
                Text("未安装").font(.caption).foregroundStyle(.tertiary)
            }
            if entry.custom {
                Text("自定义").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: enabledBinding(entry, category))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(height: listRowContentHeight)
    }

    // 列表底部 +/- 控件；- 仅对选中的自定义项可用（内置项不可删）。
    private func listFooterBar(category: AppCategory) -> some View {
        HStack(spacing: 4) {
            Button { pickApp(category) } label: {
                Image(systemName: "plus").frame(width: 22, height: 18)
            }
            .help("添加自定义 App")
            Button { removeSelected(category) } label: {
                Image(systemName: "minus").frame(width: 22, height: 18)
            }
            .disabled(!canRemoveSelected(category))
            .help("移除选中的自定义项（内置项不可删）")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private var corruptBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
            Text("配置文件损坏，已备份为 config.json.bak，当前使用默认设置")
            Spacer()
            Button("打开配置目录") { openConfigDirectory() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.red.opacity(0.85))
        .foregroundStyle(.white)
    }

    private var extensionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("访达扩展尚未启用，右键菜单不会出现")
            Spacer()
            Button("去启用") { store.openExtensionSettings() }
            Button {
                store.refreshExtensionState()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新检测")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.9))
        .foregroundStyle(.white)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    // 非常淡的竖分隔线，自动适配深浅色；上下留边距不贴边。
    private var columnDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 14)
    }

    // MARK: - 操作

    private func openConfigDirectory() {
        let dir = (store.configPath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    private func openExtensionSettings() {
        store.openExtensionSettings()
    }

    private func pickApp(_ category: AppCategory) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "添加"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.appSupportsOpeningFolder(url) {
            store.addCustomApp(at: url, category: category)
        } else {
            promptUnsupported(url, category)
        }
    }

    // 该 App 未声明可打开目录：警告但允许用户仍然添加。
    private func promptUnsupported(_ appURL: URL, _ category: AppCategory) {
        let name = appURL.deletingPathExtension().lastPathComponent
        let alert = NSAlert()
        alert.messageText = "“\(name)” 可能不支持以目录方式打开"
        alert.informativeText = "该应用未声明可打开文件夹，从右键菜单点击它时可能无法正常打开目录。仍要添加吗？"
        alert.addButton(withTitle: "仍然添加")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            store.addCustomApp(at: appURL, category: category)
        }
    }

    private func selectedEntry(_ category: AppCategory) -> AppEntry? {
        let sel: String?
        switch selection {
        case .terminal(let id) where category == .terminal: sel = id
        case .editor(let id) where category == .editor: sel = id
        default: sel = nil
        }
        return store.entries(category).first { $0.bundleId == sel }
    }

    private func canRemoveSelected(_ category: AppCategory) -> Bool {
        selectedEntry(category)?.custom == true
    }

    private func removeSelected(_ category: AppCategory) {
        guard let entry = selectedEntry(category), entry.custom else { return }
        store.removeCustom(entry, category: category)
    }

    // MARK: - 绑定

    // 把全局 selection 映射成各 List 需要的 Binding；某 List 选中即改写全局，
    // 其它 List 的 get 随之返回 nil → 自动取消，实现「全局单选」。
    private func appSelBinding(_ category: AppCategory) -> Binding<String?> {
        Binding(
            get: {
                switch selection {
                case .terminal(let id) where category == .terminal: return id
                case .editor(let id) where category == .editor: return id
                default: return nil
                }
            },
            set: { newValue in
                if let id = newValue {
                    selection = (category == .terminal) ? .terminal(id) : .editor(id)
                } else {
                    selection = nil // 点空白取消
                }
            })
    }

    private var commandSelBinding: Binding<String?> {
        Binding(
            get: { if case .command(let id) = selection { return id } else { return nil } },
            set: { newValue in selection = newValue.map { .command($0) } })
    }

    private func itemToggle(_ title: String,
                            _ keyPath: WritableKeyPath<CoreSettings.Items, Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle("", isOn: itemBinding(keyPath))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(height: listRowContentHeight)
    }

    private func itemBinding(_ keyPath: WritableKeyPath<CoreSettings.Items, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings.items[keyPath: keyPath] },
            set: { store.settings.items[keyPath: keyPath] = $0; store.persist() })
    }

    private func enabledBinding(_ entry: AppEntry, _ category: AppCategory) -> Binding<Bool> {
        Binding(
            get: { entry.enabled },
            set: { store.setEnabled(entry, on: $0, category: category) })
    }
}

private extension View {
    // 内容不足时也允许纵向橡皮筋回弹（macOS 13.3+）；旧系统原样返回。
    @ViewBuilder func alwaysBounce() -> some View {
        if #available(macOS 13.3, *) {
            self.scrollBounceBehavior(.always, axes: .vertical)
        } else {
            self
        }
    }
}

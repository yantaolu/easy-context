import SwiftUI
import UniformTypeIdentifiers
import EasyContextCore

// SwiftUI 也有个 Settings（场景）类型，显式指向我们的配置类型以消歧。
private typealias CoreSettings = EasyContextCore.Settings

struct ContentView: View {
    @StateObject private var store = SettingsStore()
    @State private var terminalSel: String?
    @State private var editorSel: String?

    var body: some View {
        VStack(spacing: 0) {
            if !store.extensionEnabled { extensionBanner }
            topPart
                .fixedSize(horizontal: false, vertical: true) // 上半按内容自适应高度
            Divider().padding(.horizontal, 20) // 横分隔不顶到头，与内容同边距
            bottomPart // 下半占剩余空间
        }
        .frame(width: 820, height: 507) // 宽窗口，高:宽 ≈ 0.618
    }

    // MARK: - 上半：菜单项 | 外观 + 其他

    private var topPart: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("菜单项")
                itemToggle("复制完整路径", \.copyFullPath)
                itemToggle("复制相对路径", \.copyRelativePath)
                itemToggle("新建文件", \.newFile)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            columnDivider

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("菜单图标")
                    Picker("", selection: Binding(
                        get: { store.settings.appearance.appIconStyle },
                        set: { store.settings.appearance.appIconStyle = $0; store.persist() })) {
                        Text("黑白").tag(CoreSettings.AppIconStyle.monochrome)
                        Text("彩色").tag(CoreSettings.AppIconStyle.color)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("其他")
                    Button("打开配置目录") { openConfigDirectory() }
                        .buttonStyle(.link)
                    Button("访达扩展设置…") { openExtensionSettings() }
                        .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
    }

    // MARK: - 下半：终端 | 编辑器（两列间留间距、无分隔线）

    private var bottomPart: some View {
        HStack(alignment: .top, spacing: 24) {
            appColumn("终端", category: .terminal)
            columnDivider
            appColumn("编辑器", category: .editor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxHeight: .infinity)
    }

    private func appColumn(_ title: String, category: AppCategory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(title)
            List(selection: selectionBinding(category)) {
                ForEach(store.entries(category)) { entry in
                    appRow(entry, category: category)
                        .tag(entry.bundleId)
                        .listRowSeparator(.hidden) // 应用之间不要横分隔线
                }
            }
            .listStyle(.inset)
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
        .padding(.vertical, 5)
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

    // 非常淡的竖分隔线，自动适配深浅色。
    private var columnDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 4)
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
        let sel = category == .terminal ? terminalSel : editorSel
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

    private func selectionBinding(_ category: AppCategory) -> Binding<String?> {
        category == .terminal ? $terminalSel : $editorSel
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

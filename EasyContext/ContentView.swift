import SwiftUI
import EasyContextCore

// SwiftUI 也有个 Settings（场景）类型，显式指向我们的配置类型以消歧。
private typealias CoreSettings = EasyContextCore.Settings

struct ContentView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        Form {
            Section("菜单项") {
                Toggle("复制完整路径", isOn: itemBinding(\.copyFullPath))
                Toggle("复制相对路径（相对 git 根）", isOn: itemBinding(\.copyRelativePath))
                Toggle("新建文件", isOn: itemBinding(\.newFile))
            }

            categorySection("终端", apps: store.detectedTerminals, category: .terminal)
            categorySection("编辑器", apps: store.detectedEditors, category: .editor)

            Section("外观") {
                Picker("菜单图标", selection: Binding(
                    get: { store.settings.appearance.appIconStyle },
                    set: { store.settings.appearance.appIconStyle = $0; store.persist() })) {
                    Text("黑白").tag(CoreSettings.AppIconStyle.monochrome)
                    Text("彩色").tag(CoreSettings.AppIconStyle.color)
                }
                .pickerStyle(.segmented)
            }

            Section("配置文件") {
                Text(store.configPath)
                    .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: store.configPath)])
                }
                .buttonStyle(.link)
            }

            Section {
                Button("打开「访达扩展」设置…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                Text("首次使用需在此勾选启用 EasyContextFinder 扩展。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 777) // 黄金分割 1:1.618
    }

    // MARK: - 分类区块

    @ViewBuilder
    private func categorySection(_ title: String, apps: [KnownApp], category: AppCategory) -> some View {
        Section(title) {
            Toggle("显示全部检测到的", isOn: showAllBinding(category))
            if !showAll(category) {
                if apps.isEmpty {
                    Text("未检测到").foregroundStyle(.secondary)
                } else {
                    ForEach(apps) { app in
                        Toggle(isOn: Binding(
                            get: { store.isEnabled(app) },
                            set: { store.setEnabled(app, on: $0) })) {
                            Label {
                                Text(app.displayName)
                            } icon: {
                                appIcon(app)
                            }
                        }
                    }
                }
            }
        }
    }

    private func appIcon(_ app: KnownApp) -> Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: app.category == .terminal
                     ? "terminal" : "chevron.left.forwardslash.chevron.right")
    }

    // MARK: - 绑定

    private func itemBinding(_ keyPath: WritableKeyPath<CoreSettings.Items, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings.items[keyPath: keyPath] },
            set: { store.settings.items[keyPath: keyPath] = $0; store.persist() })
    }

    private func showAll(_ category: AppCategory) -> Bool {
        category == .terminal ? store.settings.terminals.showAll : store.settings.editors.showAll
    }

    private func showAllBinding(_ category: AppCategory) -> Binding<Bool> {
        Binding(
            get: { showAll(category) },
            set: { value in
                if category == .terminal {
                    store.settings.terminals.showAll = value
                } else {
                    store.settings.editors.showAll = value
                }
                store.persist()
            })
    }
}

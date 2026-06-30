import SwiftUI
import EasyContextCore

struct ContentView: View {
    @StateObject private var store = SettingsStore()

    var body: some View {
        Form {
            Section("菜单项") {
                Toggle("复制完整路径", isOn: Binding(
                    get: { store.settings.copyFullPathEnabled },
                    set: { store.settings.copyFullPathEnabled = $0; store.persist() }))
                Toggle("复制相对路径（相对 git 根）", isOn: Binding(
                    get: { store.settings.copyRelativePathEnabled },
                    set: { store.settings.copyRelativePathEnabled = $0; store.persist() }))
                Toggle("新建文件", isOn: Binding(
                    get: { store.settings.newFileEnabled },
                    set: { store.settings.newFileEnabled = $0; store.persist() }))
            }

            Section("终端") {
                ForEach(store.detectedTerminals) { app in appToggle(app) }
                if store.detectedTerminals.isEmpty {
                    Text("未检测到终端").foregroundStyle(.secondary)
                }
            }

            Section("编辑器") {
                ForEach(store.detectedEditors) { app in appToggle(app) }
                if store.detectedEditors.isEmpty {
                    Text("未检测到编辑器").foregroundStyle(.secondary)
                }
            }

            Section("新建文件默认模板") {
                Picker("模板", selection: Binding(
                    get: { store.settings.defaultTemplate },
                    set: { store.settings.defaultTemplate = $0; store.persist() })) {
                    ForEach(FileTemplate.allCases, id: \.self) { t in
                        Text(t.displayName).tag(t)
                    }
                }
            }

            Section {
                Button("打开「访达扩展」设置…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("首次使用需在此勾选启用 EasyContextFinder 扩展。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    private func appToggle(_ app: KnownApp) -> some View {
        Toggle(app.displayName, isOn: Binding(
            get: { store.isEnabled(app) },
            set: { store.toggle(app, on: $0) }))
    }
}

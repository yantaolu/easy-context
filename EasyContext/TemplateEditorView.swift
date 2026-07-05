import SwiftUI
import EasyContextCore

/// 终端启动模板编辑器（sheet）：列出**全部已安装终端**（含尚无模板的），
/// 可视化编辑覆盖模板、一键恢复内置默认——不再需要手改 config.json。
/// 无模板终端（Warp/Hyper 等）在此配好模板后即可被选为执行终端。
struct TemplateEditorView: View {
    @ObservedObject var store: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?   // 终端 bundleId
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Terminal Launch Templates").font(.headline)
            Text("Terminals need a launch template to run commands. Terminals without one can't be used as the execution terminal until you add a template here.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                terminalList
                editorColumn
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 680, height: 420)
        .onChange(of: selection) { _ in loadDraft() }
    }

    private var terminalList: some View {
        List(selection: $selection) {
            ForEach(store.allInstalledTerminals) { t in
                HStack(spacing: 6) {
                    Text(t.name)
                    Spacer()
                    statusTag(t.bundleId)
                }
                .tag(t.bundleId)
            }
        }
        .listStyle(.bordered)
        .frame(width: 230)
    }

    // 状态标签：无模板的终端用橙色提醒（正是需要用户来补的那类）。
    @ViewBuilder private func statusTag(_ bundleId: String) -> some View {
        let info = store.templateInfo(for: bundleId)
        if info.isOverridden {
            Text("Custom override").font(.caption).foregroundStyle(.secondary)
        } else if info.hasBuiltin {
            Text("Built-in template").font(.caption).foregroundStyle(.tertiary)
        } else {
            Text("No template").font(.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var editorColumn: some View {
        if let bundleId = selection {
            let info = store.templateInfo(for: bundleId)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(terminalName(bundleId)).font(.subheadline.weight(.semibold))
                    statusTag(bundleId)
                    Spacer()
                }
                TextEditor(text: $draft)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.12)))
                Text("Placeholders: {dir} = target directory, {cmd} = command; replaced with \"$EC_DIR\"/\"$EC_CMD\" at run time — don't add quotes. $EC_SHELL = the user's login shell.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if info.hasBuiltin {
                        Button("Restore Default") {
                            store.setTemplateOverride("", for: bundleId)
                            loadDraft()
                        }
                        .disabled(!info.isOverridden)
                    }
                    Spacer()
                    Button("Save") {
                        store.setTemplateOverride(draft, for: bundleId)
                        loadDraft() // 与落盘后的生效值同步（空串→回退内置）
                    }
                    .disabled(draft == info.effective)
                }
            }
        } else {
            VStack {
                Spacer()
                Text("Select a terminal to edit its launch template.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func terminalName(_ bundleId: String) -> String {
        store.allInstalledTerminals.first { $0.bundleId == bundleId }?.name ?? bundleId
    }

    private func loadDraft() {
        if let id = selection { draft = store.templateInfo(for: id).effective }
    }
}

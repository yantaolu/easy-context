import Foundation
import AppKit
import EasyContextCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings

    private let store = ConfigStore()

    init() {
        self.settings = store.load()
        // 首次运行写出默认配置文件，方便用户看到/手改。
        if !store.hasStored() { try? store.save(settings) }
    }

    var configPath: String { store.path }

    private var detector: AppDetector {
        AppDetector(isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    var detectedTerminals: [KnownApp] { detector.installed(from: KnownApps.terminals) }
    var detectedEditors: [KnownApp] { detector.installed(from: KnownApps.editors) }

    func persist() {
        try? store.save(settings)
    }

    func isEnabled(_ app: KnownApp) -> Bool {
        selection(for: app.category).enabled.contains(app.bundleId)
    }

    func setEnabled(_ app: KnownApp, on: Bool) {
        func update(_ sel: inout Settings.AppSelection) {
            if on {
                if !sel.enabled.contains(app.bundleId) { sel.enabled.append(app.bundleId) }
            } else {
                sel.enabled.removeAll { $0 == app.bundleId }
            }
        }
        switch app.category {
        case .terminal: update(&settings.terminals)
        case .editor: update(&settings.editors)
        }
        persist()
    }

    private func selection(for category: AppCategory) -> Settings.AppSelection {
        category == .terminal ? settings.terminals : settings.editors
    }
}

import Foundation
import AppKit
import EasyContextCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings

    private let store = ConfigStore()

    init() {
        self.settings = store.load()
        seedEnabledIfFirstRun()
    }

    private var detector: AppDetector {
        AppDetector(isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil })
    }

    var detectedTerminals: [KnownApp] { detector.installed(from: KnownApps.terminals) }
    var detectedEditors: [KnownApp] { detector.installed(from: KnownApps.editors) }

    /// 首次运行：默认勾选所有已检测到的 App。
    private func seedEnabledIfFirstRun() {
        if !store.hasStored() {
            settings.enabledTerminalBundleIds = detectedTerminals.map(\.bundleId)
            settings.enabledEditorBundleIds = detectedEditors.map(\.bundleId)
            persist()
        }
    }

    func persist() {
        try? store.save(settings)
    }

    func isEnabled(_ app: KnownApp) -> Bool {
        switch app.category {
        case .terminal: return settings.enabledTerminalBundleIds.contains(app.bundleId)
        case .editor: return settings.enabledEditorBundleIds.contains(app.bundleId)
        }
    }

    func toggle(_ app: KnownApp, on: Bool) {
        func update(_ ids: inout [String]) {
            if on { if !ids.contains(app.bundleId) { ids.append(app.bundleId) } }
            else { ids.removeAll { $0 == app.bundleId } }
        }
        switch app.category {
        case .terminal: update(&settings.enabledTerminalBundleIds)
        case .editor: update(&settings.enabledEditorBundleIds)
        }
        persist()
    }
}

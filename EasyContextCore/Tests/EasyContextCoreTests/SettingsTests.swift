import XCTest
@testable import EasyContextCore

final class SettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "test.easycontext.settings"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_load_returnsDefaults_whenEmpty() {
        let d = makeDefaults()
        let s = Settings.load(from: d)
        XCTAssertTrue(s.copyFullPathEnabled)
        XCTAssertTrue(s.copyRelativePathEnabled)
        XCTAssertTrue(s.newFileEnabled)
        XCTAssertEqual(s.defaultTemplate, .blank)
        XCTAssertEqual(s.enabledTerminalBundleIds, [])
    }

    func test_saveThenLoad_roundTrips() {
        let d = makeDefaults()
        var s = Settings()
        s.enabledTerminalBundleIds = ["com.googlecode.iterm2"]
        s.enabledEditorBundleIds = ["com.microsoft.VSCode"]
        s.defaultTemplate = .markdown
        s.copyFullPathEnabled = false
        s.save(to: d)

        let loaded = Settings.load(from: d)
        XCTAssertEqual(loaded, s)
    }
}

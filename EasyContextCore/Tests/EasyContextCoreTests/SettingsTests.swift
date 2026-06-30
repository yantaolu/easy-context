import XCTest
@testable import EasyContextCore

final class SettingsTests: XCTestCase {
    func test_defaultInit_hasExpectedDefaults() {
        let s = Settings()
        XCTAssertEqual(s.version, 1)
        XCTAssertTrue(s.items.copyFullPath)
        XCTAssertTrue(s.items.copyRelativePath)
        XCTAssertTrue(s.items.newFile)
        XCTAssertTrue(s.terminals.showAll)
        XCTAssertEqual(s.terminals.enabled, [])
        XCTAssertTrue(s.editors.showAll)
        XCTAssertEqual(s.appearance.appIconStyle, .monochrome)
    }

    // 手改文件少写字段时应回退默认值，而非解码失败。
    func test_decode_partialJSON_fillsDefaults() throws {
        let json = """
        { "terminals": { "showAll": false, "enabled": ["com.googlecode.iterm2"] } }
        """
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        XCTAssertFalse(s.terminals.showAll)
        XCTAssertEqual(s.terminals.enabled, ["com.googlecode.iterm2"])
        XCTAssertTrue(s.items.copyFullPath)
        XCTAssertTrue(s.editors.showAll)
        XCTAssertEqual(s.appearance.appIconStyle, .monochrome)
    }

    func test_visibleApps_showAll_returnsAll() {
        let apps = [
            KnownApp(bundleId: "a", displayName: "A", category: .terminal),
            KnownApp(bundleId: "b", displayName: "B", category: .terminal),
        ]
        let s = Settings()
        XCTAssertEqual(s.visibleApps(apps, selection: .init(showAll: true)).map(\.bundleId), ["a", "b"])
    }

    func test_visibleApps_selected_filtersAndOrders() {
        let apps = [
            KnownApp(bundleId: "a", displayName: "A", category: .terminal),
            KnownApp(bundleId: "b", displayName: "B", category: .terminal),
            KnownApp(bundleId: "c", displayName: "C", category: .terminal),
        ]
        let s = Settings()
        let sel = Settings.AppSelection(showAll: false, enabled: ["c", "a", "zzz-not-installed"])
        XCTAssertEqual(s.visibleApps(apps, selection: sel).map(\.bundleId), ["c", "a"])
    }
}

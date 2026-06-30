import XCTest
@testable import EasyContextCore

final class SettingsTests: XCTestCase {
    func test_defaultInit_hasExpectedDefaults() {
        let s = Settings()
        XCTAssertTrue(s.copyFullPathEnabled)
        XCTAssertTrue(s.copyRelativePathEnabled)
        XCTAssertTrue(s.newFileEnabled)
        XCTAssertEqual(s.defaultTemplate, .blank)
        XCTAssertEqual(s.enabledTerminalBundleIds, [])
        XCTAssertEqual(s.enabledEditorBundleIds, [])
    }
}

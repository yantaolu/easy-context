import XCTest
@testable import EasyContextCore

final class SmokeTests: XCTestCase {
    func test_version_isNotEmpty() {
        XCTAssertFalse(easyContextCoreVersion().isEmpty)
    }
}

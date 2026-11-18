import XCTest
@testable import EasyContextCore

final class IPCSchemeTests: XCTestCase {
    func test_acceptsReleaseAndDebugSchemes() {
        XCTAssertEqual(IPCScheme.resolve("easycontext"), "easycontext")
        XCTAssertEqual(IPCScheme.resolve("easycontext-debug"), "easycontext-debug")
    }

    func test_normalizesCase() {
        XCTAssertEqual(IPCScheme.resolve("EasyContext-Debug"), "easycontext-debug")
    }

    func test_fallsBackForMissingOrInvalidValues() {
        XCTAssertEqual(IPCScheme.resolve(nil), "easycontext")
        XCTAssertEqual(IPCScheme.resolve(42), "easycontext")
        XCTAssertEqual(IPCScheme.resolve(""), "easycontext")
        XCTAssertEqual(IPCScheme.resolve("$(EC_URL_SCHEME)"), "easycontext")
        XCTAssertEqual(IPCScheme.resolve("1easy"), "easycontext")
        XCTAssertEqual(IPCScheme.resolve("easy context"), "easycontext")
        XCTAssertEqual(IPCScheme.resolve("éasy"), "easycontext")
    }

    func test_unitTestBundleUsesFallback() {
        XCTAssertEqual(IPCScheme.current, "easycontext")
    }
}

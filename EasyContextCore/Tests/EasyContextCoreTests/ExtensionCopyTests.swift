import XCTest
@testable import EasyContextCore

final class ExtensionCopyTests: XCTestCase {
    private let appex = URL(fileURLWithPath: "/Applications/EasyContext.app/Contents/PlugIns/EasyContextFinder.appex")

    func test_hostBundleIdentifier() {
        XCTAssertEqual(ExtensionCopy.hostBundleIdentifier(extensionBundleIdentifier: "com.luyantao.easycontext.finder"), "com.luyantao.easycontext")
        XCTAssertEqual(ExtensionCopy.hostBundleIdentifier(extensionBundleIdentifier: "com.luyantao.easycontext.debug.finder"), "com.luyantao.easycontext.debug")
        XCTAssertNil(ExtensionCopy.hostBundleIdentifier(extensionBundleIdentifier: "com.luyantao.easycontext"))
        XCTAssertNil(ExtensionCopy.hostBundleIdentifier(extensionBundleIdentifier: ".finder"))
    }

    func test_containingApp() {
        XCTAssertEqual(ExtensionCopy.containingApp(ofExtensionAt: appex)?.path, "/Applications/EasyContext.app")
        XCTAssertNil(ExtensionCopy.containingApp(ofExtensionAt: URL(fileURLWithPath: "/tmp/EasyContextFinder.appex")))
    }

    func test_officialCopyShowsMenu() {
        XCTAssertTrue(ExtensionCopy.isOfficial(extensionAt: appex, officialApp: URL(fileURLWithPath: "/Applications/EasyContext.app")))
        XCTAssertTrue(ExtensionCopy.isOfficial(extensionAt: appex, officialApp: URL(fileURLWithPath: "/Applications/EasyContext.app/")))
    }

    func test_strayCopyStaysSilent() {
        let stray = URL(fileURLWithPath: "/Users/u/Downloads/EasyContext.app/Contents/PlugIns/EasyContextFinder.appex")
        XCTAssertFalse(ExtensionCopy.isOfficial(extensionAt: stray, officialApp: URL(fileURLWithPath: "/Applications/EasyContext.app")))
    }

    func test_unknownInformationFailsOpen() {
        XCTAssertTrue(ExtensionCopy.isOfficial(extensionAt: appex, officialApp: nil))
        XCTAssertTrue(ExtensionCopy.isOfficial(extensionAt: URL(fileURLWithPath: "/tmp/X.appex"), officialApp: URL(fileURLWithPath: "/Applications/EasyContext.app")))
    }
}

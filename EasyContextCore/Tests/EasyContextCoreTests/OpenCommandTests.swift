import XCTest
@testable import EasyContextCore

final class OpenCommandTests: XCTestCase {
    func test_open_buildsOpenWithBundleIdAndDirectory() {
        let app = KnownApp(bundleId: "com.microsoft.VSCode",
                           displayName: "VSCode", category: .editor)
        let dir = URL(fileURLWithPath: "/Users/me/work/app")
        let spec = OpenCommand.open(app: app, directory: dir)
        XCTAssertEqual(spec.launchPath, "/usr/bin/open")
        XCTAssertEqual(spec.arguments,
                       ["-b", "com.microsoft.VSCode", "/Users/me/work/app"])
    }
}

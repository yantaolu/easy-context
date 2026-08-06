import Foundation
import XCTest
@testable import EasyContextCore

final class AppOpenRoutingTests: XCTestCase {
    func test_muxyDirectoryURL_usesDeepLinkAndRoundTripsEncodedPath() throws {
        let directory = URL(fileURLWithPath: "/tmp/Project #1 & 中文", isDirectory: true)
        let url = try XCTUnwrap(AppOpenRouting.customDirectoryURL(
            for: KnownApps.muxyBundleId,
            directory: directory
        ))

        XCTAssertEqual(url.scheme, "muxy")
        XCTAssertEqual(url.host, "open")
        XCTAssertFalse(url.absoluteString.contains(" "))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "path" }?.value,
                       directory.path)
    }

    func test_customDirectoryURL_returnsNilForGenericAppsAndNonFileURLs() {
        let directory = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        XCTAssertNil(AppOpenRouting.customDirectoryURL(for: "com.apple.Terminal",
                                                        directory: directory))
        XCTAssertNil(AppOpenRouting.customDirectoryURL(for: KnownApps.muxyBundleId,
                                                        directory: URL(string: "https://example.com")!))
    }
}

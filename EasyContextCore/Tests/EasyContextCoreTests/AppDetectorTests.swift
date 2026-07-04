import XCTest
@testable import EasyContextCore

final class AppDetectorTests: XCTestCase {
    func test_installed_filtersToInstalledBundleIds() {
        let installedSet: Set<String> = ["com.apple.Terminal", "com.microsoft.VSCode"]
        let sut = AppDetector(isInstalled: { installedSet.contains($0) })
        let result = sut.installed(from: KnownApps.all).map(\.bundleId)
        XCTAssertEqual(Set(result), installedSet)
    }

    func test_knownApps_haveUniqueBundleIds() {
        let ids = KnownApps.all.map(\.bundleId)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_knownApps_categoriesAreConsistent() {
        XCTAssertTrue(KnownApps.terminals.allSatisfy { $0.category == .terminal })
        XCTAssertTrue(KnownApps.editors.allSatisfy { $0.category == .editor })
    }

    func test_knownApps_includeOtty() {
        XCTAssertTrue(KnownApps.terminals.contains {
            $0.bundleId == "io.appmakes.otty" && $0.displayName == "Otty"
        })
    }
}

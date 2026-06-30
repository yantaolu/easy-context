import XCTest
@testable import EasyContextCore

final class ConfigStoreTests: XCTestCase {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("easycontext-test-\(ProcessInfo.processInfo.globallyUniqueString)")
            .appendingPathComponent("config.json")
    }

    func test_load_returnsDefaults_whenFileMissing() {
        let sut = ConfigStore(fileURL: tempFileURL())
        XCTAssertFalse(sut.hasStored())
        XCTAssertEqual(sut.load(), Settings())
    }

    func test_saveThenLoad_roundTrips() throws {
        let sut = ConfigStore(fileURL: tempFileURL())
        var s = Settings()
        s.terminals = [AppEntry(bundleId: "com.googlecode.iterm2", name: "iTerm", custom: false, enabled: false)]
        s.editors = [AppEntry(bundleId: "com.example.editor", name: "My Editor", custom: true, enabled: true)]
        s.items.copyFullPath = false
        s.appearance.appIconStyle = .color
        try sut.save(s)
        XCTAssertTrue(sut.hasStored())
        XCTAssertEqual(sut.load(), s)
    }

    func test_load_returnsDefaults_whenCorrupt() throws {
        let url = tempFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let sut = ConfigStore(fileURL: url)
        XCTAssertEqual(sut.load(), Settings())
    }
}

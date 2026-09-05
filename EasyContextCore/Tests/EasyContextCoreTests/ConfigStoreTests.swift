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

    func test_fileToken_includesSizeWhenModificationDateMatches() throws {
        let url = tempFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sut = ConfigStore(fileURL: url)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        try Data("a".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: url.path)
        let first = sut.fileToken()

        try Data("abcd".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: url.path)
        let second = sut.fileToken()

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.mtime, second?.mtime)
        XCTAssertNotEqual(first, second)
    }

    func test_load_returnsDefaults_whenCorrupt() throws {
        let url = tempFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let sut = ConfigStore(fileURL: url)
        XCTAssertEqual(sut.load(), Settings())
    }

    func test_templatesReference_documentsUnicodeSafeAppleScriptOverrides() throws {
        let sut = ConfigStore(fileURL: tempFileURL())
        defer { try? FileManager.default.removeItem(at: sut.templatesReferenceURL.deletingLastPathComponent()) }
        sut.writeTemplatesReference(builtin: TerminalLaunch.builtinTemplates)
        let data = try Data(contentsOf: sut.templatesReferenceURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let note = try XCTUnwrap(json["_note"] as? String)
        XCTAssertTrue(note.contains("must not use 'system attribute'"))
        XCTAssertTrue(note.contains("on run argv"))
        XCTAssertTrue(note.contains("-- \"$EC_DIR\" \"$EC_CMD\""))
        XCTAssertTrue(note.contains("Existing overrides are not migrated automatically"))
    }

    // MARK: loadOutcome 区分 missing / ok / corrupt

    func test_loadOutcome_missing() {
        let sut = ConfigStore(fileURL: tempFileURL())
        XCTAssertEqual(sut.loadOutcome(), .missing)
    }

    func test_loadOutcome_ok() throws {
        let sut = ConfigStore(fileURL: tempFileURL())
        var s = Settings(); s.items.newFile = false
        try sut.save(s)
        XCTAssertEqual(sut.loadOutcome(), .ok(s))
    }

    func test_loadOutcome_corrupt_andBackupPreservesOriginal() throws {
        let url = tempFileURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: url)
        let sut = ConfigStore(fileURL: url)
        XCTAssertEqual(sut.loadOutcome(), .corrupt)
        // 备份保留原始损坏内容
        let bak = sut.backupCorruptFile()
        XCTAssertNotNil(bak)
        XCTAssertEqual(try String(contentsOf: bak!, encoding: .utf8), "{ broken")
    }

    // MARK: IPC token

    func test_ipcToken_generatesStableAndReadable() {
        let sut = ConfigStore(fileURL: tempFileURL())
        XCTAssertEqual(sut.readIPCToken(), "") // 未生成前为空
        let t1 = sut.ensureIPCToken()
        XCTAssertFalse(t1.isEmpty)
        XCTAssertEqual(sut.ensureIPCToken(), t1)  // 稳定，不重复生成
        XCTAssertEqual(sut.readIPCToken(), t1)    // 只读也拿到同一个
    }
}

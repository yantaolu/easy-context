import XCTest
@testable import EasyContextCore

final class NewFileMakerTests: XCTestCase {
    private final class ConcurrentCreateResults: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private var failures: [Error] = []

        func append(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        func append(_ error: Error) {
            lock.lock()
            failures.append(error)
            lock.unlock()
        }

        var snapshot: (urls: [URL], failures: [Error]) {
            lock.lock()
            defer { lock.unlock() }
            return (urls, failures)
        }
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ecnf-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_create_usesRequestedName_andWritesContent() throws {
        let dir = try tempDir()
        let url = try NewFileMaker.create(template: .json, in: dir, requestedName: "data.json")
        XCTAssertEqual(url.lastPathComponent, "data.json")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{}\n")
    }

    func test_create_emptyName_usesTemplateDefault() throws {
        let dir = try tempDir()
        let url = try NewFileMaker.create(template: .markdown, in: dir, requestedName: "   ")
        XCTAssertEqual(url.lastPathComponent, FileTemplate.markdown.defaultFileName)
    }

    func test_create_appendsExtensionFromBareBase() throws {
        let dir = try tempDir()
        // 用户只输基名 → 无扩展名，得到无扩展名文件（模板扩展名不强加）
        let url = try NewFileMaker.create(template: .markdown, in: dir, requestedName: "笔记.md")
        XCTAssertEqual(url.lastPathComponent, "笔记.md")
    }

    func test_create_collision_appendsCounter_neverOverwrites() throws {
        let dir = try tempDir()
        let a = try NewFileMaker.create(template: .text, in: dir, requestedName: "a.txt")
        let b = try NewFileMaker.create(template: .text, in: dir, requestedName: "a.txt")
        XCTAssertEqual(a.lastPathComponent, "a.txt")
        XCTAssertEqual(b.lastPathComponent, "a 2.txt")
    }

    func test_create_concurrentSameName_createsUniqueFilesWithoutOverwrite() throws {
        let dir = try tempDir()
        let count = 20
        let group = DispatchGroup()
        let results = ConcurrentCreateResults()

        for _ in 0..<count {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = try NewFileMaker.create(template: .json, in: dir, requestedName: "data.json")
                    results.append(url)
                } catch {
                    results.append(error)
                }
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        let snapshot = results.snapshot
        XCTAssertTrue(snapshot.failures.isEmpty, "\(snapshot.failures)")
        XCTAssertEqual(snapshot.urls.count, count)
        XCTAssertEqual(Set(snapshot.urls.map(\.lastPathComponent)).count, count)

        for url in snapshot.urls {
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{}\n")
        }
    }

    func test_create_shell_isExecutable() throws {
        let dir = try tempDir()
        let url = try NewFileMaker.create(template: .shell, in: dir, requestedName: "run.sh")
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o755)
    }

    func test_create_stripsPathTraversal() throws {
        let dir = try tempDir()
        // 名字里带目录/穿越成分 → 只取 lastPathComponent，文件落在 dir 内
        let url = try NewFileMaker.create(template: .text, in: dir, requestedName: "../evil")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       dir.standardizedFileURL)
        XCTAssertEqual(url.lastPathComponent, "evil")
    }
}

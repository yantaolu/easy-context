import XCTest
@testable import EasyContextCore

final class RelativePathResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/me")

    func test_gitRoot_findsNearestAncestorWithDotGit() {
        let repo = URL(fileURLWithPath: "/Users/me/work/app")
        let sut = RelativePathResolver(
            gitMarkerExists: { $0.path == "/Users/me/work/app/.git" },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/work/app/src/main.swift")
        XCTAssertEqual(sut.gitRoot(for: file), repo)
    }

    func test_relativePath_insideRepo_isRelativeToRoot() {
        let sut = RelativePathResolver(
            gitMarkerExists: { $0.path == "/Users/me/work/app/.git" },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/work/app/src/main.swift")
        XCTAssertEqual(sut.relativePath(for: file), "src/main.swift")
    }

    func test_gitRoot_recognizesDotGitFile_inWorktreeOrSubmodule() throws {
        // worktree / submodule 下 `.git` 是 gitlink 文件而非目录，走真实 FS 的默认 init。
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ectest-\(UUID().uuidString)")
        let repo = tmp.appendingPathComponent("wt")
        try FileManager.default.createDirectory(
            at: repo.appendingPathComponent("src"), withIntermediateDirectories: true)
        try "gitdir: /somewhere/.git/worktrees/wt\n"
            .write(to: repo.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let sut = RelativePathResolver()
        let file = repo.appendingPathComponent("src/main.swift")
        XCTAssertEqual(sut.gitRoot(for: file)?.standardizedFileURL.path,
                       repo.standardizedFileURL.path)
        XCTAssertEqual(sut.relativePath(for: file), "src/main.swift")
    }

    func test_relativePath_outsideRepo_fallsBackToHome() {
        let sut = RelativePathResolver(
            gitMarkerExists: { _ in false },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/Desktop/note.txt")
        XCTAssertEqual(sut.relativePath(for: file), "~/Desktop/note.txt")
    }

    func test_relativePath_outsideHome_returnsAbsolute() {
        let sut = RelativePathResolver(
            gitMarkerExists: { _ in false },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Volumes/USB/data.csv")
        XCTAssertEqual(sut.relativePath(for: file), "/Volumes/USB/data.csv")
    }
}

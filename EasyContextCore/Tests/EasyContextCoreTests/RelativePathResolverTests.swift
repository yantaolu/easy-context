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

    // 家目录本身（~ 空白处右键）→ "~"，而非 "~/."。
    func test_relativePath_homeItself_returnsTilde() {
        let sut = RelativePathResolver(gitMarkerExists: { _ in false }, homeDirectory: home)
        XCTAssertEqual(sut.relativePath(for: home), "~")
    }

    // 回归：Finder 递给扩展的是 NSURL 桥接 URL，它在根目录上 deletingLastPathComponent
    // 会追加 "../" 而非停住——旧的 URL 版向上遍历在这里死循环（内存爆涨、扩展假死）。
    // 字符串版必须对桥接 URL 也正常收敛返回 nil。
    func test_gitRoot_terminatesForNSURLBridgedURLs() {
        let sut = RelativePathResolver(gitMarkerExists: { _ in false }, homeDirectory: home)
        let bridged = NSURL(fileURLWithPath: "/Users/me/Desktop/note.txt") as URL
        XCTAssertNil(sut.gitRoot(for: bridged))
        XCTAssertEqual(sut.relativePath(for: NSURL(fileURLWithPath: "/Users/me/Desktop/note.txt") as URL),
                       "~/Desktop/note.txt")
        // 根目录本身也必须终止
        XCTAssertNil(sut.gitRoot(for: NSURL(fileURLWithPath: "/") as URL))
    }
}

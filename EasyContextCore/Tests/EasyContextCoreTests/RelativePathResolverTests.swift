import XCTest
@testable import EasyContextCore

final class RelativePathResolverTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/me")

    func test_gitRoot_findsNearestAncestorWithDotGit() {
        let repo = URL(fileURLWithPath: "/Users/me/work/app")
        let sut = RelativePathResolver(
            directoryExists: { $0.path == "/Users/me/work/app/.git" },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/work/app/src/main.swift")
        XCTAssertEqual(sut.gitRoot(for: file), repo)
    }

    func test_relativePath_insideRepo_isRelativeToRoot() {
        let sut = RelativePathResolver(
            directoryExists: { $0.path == "/Users/me/work/app/.git" },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/work/app/src/main.swift")
        XCTAssertEqual(sut.relativePath(for: file), "src/main.swift")
    }

    func test_relativePath_outsideRepo_fallsBackToHome() {
        let sut = RelativePathResolver(
            directoryExists: { _ in false },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Users/me/Desktop/note.txt")
        XCTAssertEqual(sut.relativePath(for: file), "~/Desktop/note.txt")
    }

    func test_relativePath_outsideHome_returnsAbsolute() {
        let sut = RelativePathResolver(
            directoryExists: { _ in false },
            homeDirectory: home)
        let file = URL(fileURLWithPath: "/Volumes/USB/data.csv")
        XCTAssertEqual(sut.relativePath(for: file), "/Volumes/USB/data.csv")
    }
}

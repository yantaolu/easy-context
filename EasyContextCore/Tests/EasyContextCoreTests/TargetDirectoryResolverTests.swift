import XCTest
@testable import EasyContextCore

final class TargetDirectoryResolverTests: XCTestCase {
    func test_directory_returnsSelf_whenDirectory() {
        let dir = URL(fileURLWithPath: "/Users/me/projects")
        let sut = TargetDirectoryResolver(isDirectory: { $0 == dir })
        XCTAssertEqual(sut.directory(for: dir), dir)
    }

    func test_directory_returnsParent_whenFile() {
        let file = URL(fileURLWithPath: "/Users/me/projects/readme.md")
        let sut = TargetDirectoryResolver(isDirectory: { _ in false })
        XCTAssertEqual(sut.directory(for: file),
                       URL(fileURLWithPath: "/Users/me/projects"))
    }
}

import XCTest
@testable import EasyContextCore

final class UniqueNameResolverTests: XCTestCase {
    func test_uniqueName_returnsBase_whenFree() {
        let sut = UniqueNameResolver(exists: { _ in false })
        XCTAssertEqual(sut.uniqueName(base: "未命名", ext: "md"), "未命名.md")
    }

    func test_uniqueName_appendsCounter_whenTaken() {
        let taken: Set<String> = ["未命名.md", "未命名 2.md"]
        let sut = UniqueNameResolver(exists: { taken.contains($0) })
        XCTAssertEqual(sut.uniqueName(base: "未命名", ext: "md"), "未命名 3.md")
    }

    func test_uniqueName_handlesEmptyExtension() {
        let taken: Set<String> = ["未命名"]
        let sut = UniqueNameResolver(exists: { taken.contains($0) })
        XCTAssertEqual(sut.uniqueName(base: "未命名", ext: ""), "未命名 2")
    }
}
